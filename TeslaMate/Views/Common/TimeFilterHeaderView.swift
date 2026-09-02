import SwiftUI

struct TimeFilterHeaderView: View {
    @Binding var selectedFilter: DateFilterOption
    let onFilterChanged: () -> Void

    @State private var isCustomExpanded = false
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var customEndDate: Date = .now

    private let presetOptions: [DateFilterOption] = [
        .all,
        .last24Hours,
        .last3Days,
        .lastWeek,
        .lastMonth
    ]

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presetOptions) { option in
                        FilterPill(
                            title: option.label,
                            isSelected: selectedFilter == option,
                            icon: nil
                        ) {
                            if selectedFilter != option {
                                selectedFilter = option
                                withAnimation {
                                    isCustomExpanded = false
                                }
                                onFilterChanged()
                            }
                        }
                    }

                    FilterPill(
                        title: selectedFilter.isCustom ? selectedFilter.label : "Custom",
                        isSelected: selectedFilter.isCustom || isCustomExpanded,
                        icon: isCustomExpanded ? "chevron.up" : "calendar"
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isCustomExpanded.toggle()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            if isCustomExpanded {
                VStack(spacing: 12) {
                    HStack {
                        Text("Custom Range")
                            .font(.subheadline.bold())
                        Spacer()
                        Button("Apply") {
                            selectedFilter = .custom(start: customStartDate, end: customEndDate)
                            withAnimation {
                                isCustomExpanded = false
                            }
                            onFilterChanged()
                        }
                        .font(.subheadline.bold())
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                    }

                    Divider()

                    DatePicker(
                        "From",
                        selection: $customStartDate,
                        in: ...customEndDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(.subheadline)

                    DatePicker(
                        "To",
                        selection: $customEndDate,
                        in: customStartDate...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(.subheadline)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 4)
    }
}

private struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.blue : Color(.secondarySystemBackground),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
