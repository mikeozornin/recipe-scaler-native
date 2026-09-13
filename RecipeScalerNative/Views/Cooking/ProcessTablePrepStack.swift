import SwiftUI

struct ProcessTablePrepStack: View {
    let columns: [ProcessTableV1.Column]

    var body: some View {
        VStack(alignment: .leading, spacing: ProcessTableLayout.prepRowSpacing) {
            ForEach(columns, id: \.id) { column in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("recipe.process-table.prep")
                        .appBody()
                    Text(": \(column.title)")
                        .appBody()
                }
            }
        }
    }
}
