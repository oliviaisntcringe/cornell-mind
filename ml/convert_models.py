#!/usr/bin/env python3
"""Конвертация HF-моделей в CoreML (.mlpackage) для приложения CornellMind.

Использует huggingface/exporters поверх coremltools.

Модели:
  1. Embedder (тегирование) — multilingual DistilBERT, feature-extraction.
     В Swift берём средний пул по токенам и сравниваем косинусным сходством
     с кандидатными тегами.
  2. QG (генерация вопросов) — T5-family, text2text-generation.
     Экспортируются encoder.mlpackage + decoder.mlpackage.

Запуск:
    python3 convert_models.py                 # обе модели, значения по умолчанию
    python3 convert_models.py --tagging=off   # только QG
    python3 convert_models.py --qg=off        # только тегирование

Переменные окружения позволяют подменить модели в CI:
    CM_EMBED_MODEL, CM_QG_MODEL, CM_OUT, CM_AUTH_TOKEN
"""
import argparse
import os
import shutil
import subprocess
import sys
import textwrap
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = Path(os.environ.get("CM_OUT", ROOT / "CornellMind" / "Resources" / "Models"))
QGT_DIR = Path(os.environ.get("CM_QGT_DIR", ROOT / "ml" / "qg_tmp"))

EMBED_MODEL = os.environ.get("CM_EMBED_MODEL", "distilbert-base-multilingual-cased")
# T5-family QG (ml). mT5 — вариант для русского (google/mt5-small);
# смена модели не требует правок Swift-кода (тот же набор входов/выходов).
QG_MODEL = os.environ.get("CM_QG_MODEL", "google/flan-t5-small")


QUANTIZE = os.environ.get("CM_QUANTIZE", "float32")  # float16 быстрее, но у T5 в float16 бывают NaN


def log(msg: str) -> None:
    print(f"[convert] {msg}", flush=True)


def run_transformer(cmd: list[str]) -> None:
    log("$ " + " ".join(cmd))
    subprocess.run(cmd, check=True)


def build_cli_args(extra: list[str]) -> list[str]:
    return [
        sys.executable,
        "-m", "exporters.coreml",
        "--framework", "pt",
        "--quantize", QUANTIZE,
        "--compute_units", "cpu_and_gpu",
        # Значение 1e-4 по умолчанию слишком строго для float16 —
        # разница ~1e-3-1e-2 ожидаема и допустима (см. README exporters).
        "--atol", "0.05",
    ] + extra


def convert_embedder(model_id: str, out_pkg: Path) -> None:
    log(f"== Embedder: {model_id} ==")
    out_pkg.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_pkg.parent / "_embed_tmp"
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)

    run_transformer(
        build_cli_args(["--model", model_id, "--feature", "feature-extraction", str(tmp)])
    )

    # exporters кладёт результат как Model.mlpackage
    src = tmp / "Model.mlpackage"
    if not src.exists():
        raise FileNotFoundError(f"Ожидался {src}")
    if out_pkg.exists():
        shutil.rmtree(out_pkg)
    shutil.move(str(src), str(out_pkg))
    shutil.rmtree(tmp)
    log(f"Embedder сохранён: {out_pkg}")


def convert_qg(model_id: str) -> tuple[Path, Path]:
    log(f"== QG: {model_id} ==")
    QGT_DIR.mkdir(parents=True, exist_ok=True)

    model_path = model_id
    # mT5 не зарегистрирован в exporters (архитектура == T5), а веса у него в .bin,
    # что требует torch>=2.6. Подготавливаем локальную копию:
    #  1) качаем файлы;  2) конвертируем pytorch_model.bin -> model.safetensors;
    #  3) подменяем model_type: mt5 -> t5 в config.json.
    if model_id.startswith("mt5") or "mt5" in model_id:
        model_path = prepare_mt5(model_id)

    run_transformer(
        build_cli_args(["--model", model_path, "--feature", "text2text-generation", str(QGT_DIR)])
    )

    enc = QGT_DIR / "encoder_Model.mlpackage"
    dec = QGT_DIR / "decoder_Model.mlpackage"
    if not enc.exists() or not dec.exists():
        missing = [p for p in (enc, dec) if not p.exists()]
        raise FileNotFoundError(f"QГ-конверсия: не хватает {[str(p) for p in missing]}")
    return enc, dec


def prepare_mt5(model_id: str) -> Path:
    """Скачивает mT5, конвертирует веса в safetensors и патчит config под T5."""
    from huggingface_hub import snapshot_download

    local = QGT_DIR.parent / "mt5_local"
    if local.exists():
        import shutil
        shutil.rmtree(local)

    log(f"Скачивание {model_id} → {local}")
    snapshot_download(
        model_id,
        local_dir=str(local),
        allow_patterns=[
            "config.json",
            "pytorch_model.bin",
            "spiece.model",
            "tokenizer_config.json",
            "special_tokens_map.json",
            "generation_config.json",
        ],
    )

    import json

    import torch
    import safetensors.torch

    bin_path = local / "pytorch_model.bin"
    st_path = local / "model.safetensors"
    if bin_path.exists() and not st_path.exists():
        log("Конвертация pytorch_model.bin → model.safetensors")
        state = torch.load(bin_path, map_location="cpu")
        state = {k: v.detach().clone().contiguous() for k, v in state.items()}
        safetensors.torch.save_file(state, str(st_path), metadata={"format": "pt"})
        bin_path.unlink()

    cfg = json.loads((local / "config.json").read_text())
    if cfg.get("model_type") == "mt5":
        log("Патч config.json: model_type mt5 → t5")
        cfg["model_type"] = "t5"
        (local / "config.json").write_text(json.dumps(cfg, indent=2))

    return local


def prepare_tokenizers(tok_root: Path) -> None:
    """Генерирует fast-токенизаторы (tokenizer.json) для QG и Embedder
    и раскладывает их по папкам, которые ждёт swift-transformers."""
    from transformers import AutoTokenizer
    import json as _json

    def dump(model_id: str, folder_name: str, mt5_local: Path | None = None) -> None:
        out = tok_root / folder_name
        out.mkdir(parents=True, exist_ok=True)
        src = str(mt5_local) if mt5_local is not None else model_id
        tok = AutoTokenizer.from_pretrained(src, use_fast=True)
        tok.save_pretrained(out)

        # mT5: HF пишет model.unk_id, а swift-transformers ждёт model.unkId
        tj = out / "tokenizer.json"
        if tj.exists():
            data = _json.loads(tj.read_text())
            model = data.get("model", {})
            if "unk_id" in model and "unkId" not in model:
                model["unkId"] = model["unk_id"]
                tj.write_text(_json.dumps(data))
                log(f"  + unkId в {folder_name}/tokenizer.json")

    log("Подготовка токенизаторов…")
    mt5_local = QGT_DIR.parent / "mt5_local"
    dump(QG_MODEL, "QG", mt5_local if mt5_local.exists() else None)
    dump(EMBED_MODEL, "Embedder")


def main() -> None:
    parser = argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter,
                                     description=textwrap.dedent(__doc__))
    parser.add_argument("--tagging", choices=["on", "off"], default="on")
    parser.add_argument("--qg", choices=["on", "off"], default="on")
    parser.add_argument("--output", type=Path, default=OUT_DIR)
    args = parser.parse_args()

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    started = time.time()

    if args.tagging == "on":
        convert_embedder(EMBED_MODEL, output / "Embedder.mlpackage")

    if args.qg == "on":
        enc, dec = convert_qg(QG_MODEL)
        enc_out = output / "QGEncoder.mlpackage"
        dec_out = output / "QGDecoder.mlpackage"
        for s, d in ((enc, enc_out), (dec, dec_out)):
            if d.exists():
                shutil.rmtree(d)
            shutil.copytree(s, d)
        log(f"QG сохранён:\n  {enc_out}\n  {dec_out}")
        if output.resolve() != QGT_DIR.resolve():
            shutil.rmtree(QGT_DIR)

    if args.tagging == "on" or args.qg == "on":
        prepare_tokenizers(output.parent / "Tokenizer")

    # Сопроводительная документация по токенизаторам для Swift-интеграции
    tok_md = output / "TOKENIZERS.md"
    tok_md.write_text(
        "Токенизаторы для swift-transformers берутся из оригинальных HF-репозиториев "
        "(tokenizer.json + tokenizer_config.json).\n",
        encoding="utf-8",
    )

    log(f"Готово за {time.time() - started:.0f}s. Результаты в: {output}")
    for f in sorted(output.iterdir()):
        log(f"  - {f.name}")


if __name__ == "__main__":
    main()