import SwiftUI

struct MindMapView: View {
    let note: Note
    @State private var zoom: CGFloat = 1.0
    @State private var tree: MindMapNode?

    private var resolvedTree: MindMapNode {
        if let tree { return tree }
        let built = MindMapBuilder.build(from: note)
        Task { @MainActor in self.tree = built }
        return built
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Rectangle()
                    .fill(INTR.lime)
                    .frame(width: 10, height: 26)
                Text("MIND MAP")
                    .font(INTR.fontHeader)
                    .foregroundColor(INTR.text)
                Spacer()
            }
            .padding(.horizontal, 8)
            GeometryReader { geo in
                let layout = RadialLayout(root: resolvedTree, in: geo.size)
                Canvas { context, size in
                    drawEdges(layout, context: &context)
                    for node in layout.drawnNodes {
                        let point = layout.position(of: node.id)
                        drawNode(node, at: point, context: &context)
                    }
                }
                .background(INTR.background)
                .scaleEffect(zoom)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(max(value.magnification, 0.5), 2.5)
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) { zoom = 1.0 }
                        }
                )
            }
        }
        .padding(8)
        .background(INTR.background)
    }

    // MARK: - Drawing

    private func drawNode(_ node: MindMapNode, at point: CGPoint, context: inout GraphicsContext) {
        let isRoot = node.text == resolvedTree.text && node.children.count > 0
        let boxWidth: CGFloat = isRoot ? 140 : 120
        let boxHeight: CGFloat = 34
        let rect = CGRect(
            x: point.x - boxWidth / 2,
            y: point.y - boxHeight / 2,
            width: boxWidth,
            height: boxHeight
        )

let path = Path(roundedRect: rect, cornerRadius: 0)

        context.fill(
            path,
            with: .color(isRoot ? INTR.graphite : Color(hex: 0xF2EFE6))
        )
        context.stroke(path, with: .color(INTR.border), lineWidth: 2)

        let shortened = node.text.count > 40 ? String(node.text.prefix(37)) + "…" : node.text
        let label = Text(verbatim: shortened.uppercased())
            .font(.system(.caption2, design: .default).weight(.bold))
            .foregroundColor(isRoot ? INTR.lime : INTR.text)
        context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    private func drawEdges(_ layout: RadialLayout, context: inout GraphicsContext) {
        for edge in layout.edges {
            let from = layout.position(of: edge.parent)
            let to = layout.position(of: edge.child)
            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: midpoint(from, to))
            context.stroke(
                path,
                with: .color(INTR.concrete.opacity(0.7)),
                lineWidth: 2
            )
        }
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(
            x: (a.x + b.x) / 2,
            y: min(a.y, b.y)
        )
    }
}

// MARK: - Layout

/// Радиальная раскладка: корень в центре, дети раскручены по кругу,
/// внуки укладываются по спирали.
struct RadialLayout {
    struct Edge: Identifiable {
        let id = UUID()
        let parent: UUID
        let child: UUID
    }

    let root: MindMapNode
    let positions: [UUID: CGPoint]
    let edges: [Edge]

    init(root: MindMapNode, in size: CGSize) {
        self.root = root
        var positions: [UUID: CGPoint] = [:]
        var edges: [Edge] = []

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let baseRadius = min(size.width, size.height) / 3.2

        positions[root.id] = center

        let children = root.children
        if !children.isEmpty {
            for (index, child) in children.enumerated() {
                let angle = Double.pi * 2 * Double(index) / Double(max(children.count, 1)) - Double.pi / 2
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * baseRadius,
                    y: center.y + CGFloat(sin(angle)) * baseRadius
                )
                positions[child.id] = point
                edges.append(Edge(parent: root.id, child: child.id))

                let grandchildren = child.children.count > 5 ? Array(child.children.prefix(5)) : child.children
                for (gIndex, grandchild) in grandchildren.enumerated() {
                    let spiral = 1.35 + Double(gIndex) * 0.22
                    let gRadius = baseRadius * CGFloat(spiral)
                    let gAngle = angle + Double(gIndex) * 0.5
                    let gPoint = CGPoint(
                        x: center.x + CGFloat(cos(gAngle)) * gRadius,
                        y: center.y + CGFloat(sin(gAngle)) * gRadius
                    )
                    positions[grandchild.id] = gPoint
                    edges.append(Edge(parent: child.id, child: grandchild.id))
                }
            }
        }

        self.positions = positions
        self.edges = edges
    }

    var allNodes: [MindMapNode] {
        collect(root)
    }

    /// Только узлы, у которых есть позиция (иначе рисовались бы в углу).
    var drawnNodes: [MindMapNode] {
        allNodes.filter { positions[$0.id] != nil }
    }

    var drawnCount: Int {
        positions.count
    }

    func position(of id: UUID) -> CGPoint {
        positions[id] ?? .zero
    }

    private func collect(_ node: MindMapNode) -> [MindMapNode] {
        [node] + node.children.flatMap(collect)
    }
}