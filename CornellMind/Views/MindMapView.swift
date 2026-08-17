import SwiftUI

struct MindMapView: View {
    let note: Note
    @State private var zoom: CGFloat = 1.0

    private var tree: MindMapNode {
        MindMapBuilder.build(from: note)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Mind Map")
                .font(.headline)
            GeometryReader { geo in
                let layout = RadialLayout(root: tree, in: geo.size)
                Canvas { context, size in
                    drawEdges(layout, context: &context)
                    for node in layout.allNodes {
                        let point = layout.position(of: node.id)
                        drawNode(node, at: point, context: &context)
                    }
                }
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
    }

    // MARK: - Drawing

    private func drawNode(_ node: MindMapNode, at point: CGPoint, context: inout GraphicsContext) {
        let isRoot = node.text == tree.text && node.children.count > 0
        let boxWidth: CGFloat = isRoot ? 140 : 120
        let boxHeight: CGFloat = 34
        let rect = CGRect(
            x: point.x - boxWidth / 2,
            y: point.y - boxHeight / 2,
            width: boxWidth,
            height: boxHeight
        )

        let path = Path(roundedRect: rect, cornerRadius: 8)

        context.fill(
            path,
            with: .color(isRoot ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        )
        context.stroke(path, with: .color(Color.secondary.opacity(0.5)), lineWidth: 1)

        let shortened = node.text.count > 40 ? String(node.text.prefix(37)) + "…" : node.text
        let label = Text(verbatim: shortened)
            .font(.caption2)
            .foregroundColor(isRoot ? .white : .primary)
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
                with: .color(Color.secondary.opacity(0.4)),
                lineWidth: 1.5
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
                let angle = 2 * .pi * Double(index) / Double(children.count) - .pi / 2
                let point = CGPoint(
                    x: center.x + cos(angle) * baseRadius,
                    y: center.y + sin(angle) * baseRadius
                )
                positions[child.id] = point
                edges.append(Edge(parent: root.id, child: child.id))

                let grandchildren = child.children.count > 8 ? Array(child.children.prefix(8)) : child.children
                for (gIndex, grandchild) in grandchildren.enumerated() {
                    let spiral = 1.35 + Double(gIndex) * 0.22
                    let gRadius = baseRadius * spiral
                    let gAngle = angle + Double(gIndex) * 0.5
                    let gPoint = CGPoint(
                        x: center.x + cos(gAngle) * gRadius,
                        y: center.y + sin((gAngle)) * gRadius
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

    func position(of id: UUID) -> CGPoint {
        positions[id] ?? .zero
    }

    private func collect(_ node: MindMapNode) -> [MindMapNode] {
        [node] + node.children.flatMap(collect)
    }
}