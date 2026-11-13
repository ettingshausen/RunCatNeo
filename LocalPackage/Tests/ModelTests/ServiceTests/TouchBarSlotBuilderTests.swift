import Foundation
import Testing

@testable import DataSource
@testable import Model

struct TouchBarSlotBuilderTests {
    private func metric(_ metric: TouchBarMetric) -> TouchBarIndicator {
        TouchBarIndicator(
            member: .metric(metric),
            systemIcon: "icon",
            primaryText: metric.rawValue
        )
    }

    private func stock(_ id: UUID, abbreviation: String) -> StockIndicator {
        StockIndicator(
            id: id,
            abbreviation: abbreviation,
            name: abbreviation,
            changePercent: 1,
            direction: .up,
            quote: StockQuote(symbol: "sh\(abbreviation)", name: abbreviation, price: 1, changePercent: 1)
        )
    }

    @Test
    func without_stacks_every_indicator_is_its_own_slot() {
        let slots = TouchBarSlotBuilder.metricSlots(
            indicators: [metric(.cpu), metric(.memory)],
            stacks: []
        )
        #expect(slots.map(\.id) == ["member:metric:cpu", "member:metric:memory"])
        #expect(slots.allSatisfy { !$0.isStack })
    }

    @Test
    func a_stack_takes_the_position_of_its_first_member() {
        let stack = TouchBarStack(members: [.metric(.memory), .metric(.battery)])
        let slots = TouchBarSlotBuilder.metricSlots(
            indicators: [metric(.cpu), metric(.memory), metric(.storage), metric(.battery)],
            stacks: [stack]
        )
        #expect(slots.map(\.id) == ["member:metric:cpu", stack.slotID, "member:metric:storage"])
        #expect(slots[1].indicators.map(\.member) == [.metric(.memory), .metric(.battery)])
        #expect(slots[1].isStack)
    }

    @Test
    func stack_members_follow_the_configured_member_order() {
        let stack = TouchBarStack(members: [.metric(.battery), .metric(.cpu)])
        let slots = TouchBarSlotBuilder.metricSlots(
            indicators: [metric(.cpu), metric(.battery)],
            stacks: [stack]
        )
        #expect(slots.count == 1)
        #expect(slots[0].indicators.map(\.member) == [.metric(.battery), .metric(.cpu)])
    }

    @Test
    func a_stack_with_one_present_member_degrades_to_a_single_slot() {
        let stack = TouchBarStack(members: [.metric(.cpu), .metric(.storage)])
        let slots = TouchBarSlotBuilder.metricSlots(
            indicators: [metric(.cpu), metric(.memory)],
            stacks: [stack]
        )
        #expect(slots.count == 2)
        #expect(slots[0].id == stack.slotID)
        #expect(slots[0].indicators.map(\.member) == [.metric(.cpu)])
        #expect(!slots[0].isStack)
        #expect(slots[1].indicators.map(\.member) == [.metric(.memory)])
    }

    @Test
    func custom_metrics_can_share_a_stack_with_system_metrics() {
        let customID = UUID()
        let stack = TouchBarStack(members: [.customMetric(customID), .metric(.cpu)])
        let slots = TouchBarSlotBuilder.metricSlots(
            indicators: [
                metric(.cpu),
                TouchBarIndicator(member: .customMetric(customID), systemIcon: "icon", primaryText: "custom"),
            ],
            stacks: [stack]
        )
        #expect(slots.count == 1)
        #expect(slots[0].indicators.map(\.member) == [.customMetric(customID), .metric(.cpu)])
    }

    @Test
    func stocks_group_only_with_stock_members() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let stack = TouchBarStack(members: [.stock(first), .stock(second)])
        let slots = TouchBarSlotBuilder.stockSlots(
            indicators: [
                stock(first, abbreviation: "A"),
                stock(second, abbreviation: "B"),
                stock(third, abbreviation: "C"),
            ],
            stacks: [stack]
        )
        #expect(slots.map(\.id) == [stack.slotID, "member:stock:\(third.uuidString)"])
        #expect(slots[0].indicators.map(\.id) == [first, second])
        #expect(slots[1].indicators.map(\.id) == [third])
    }
}
