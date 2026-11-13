import Foundation
import Testing

@testable import DataSource

struct TouchBarStackTests {
    @Test
    func member_keys_roundtrip_through_init() {
        let members: [TouchBarMember] = [.metric(.keyboardBattery), .customMetric(UUID()), .stock(UUID())]
        for member in members {
            #expect(TouchBarMember(key: member.key) == member)
        }
        #expect(TouchBarMember(key: "metric:cpu") == .metric(.cpu))
        #expect(TouchBarMember(key: "nope") == nil)
        #expect(TouchBarMember(key: "metric:unknown") == nil)
        #expect(TouchBarMember(key: "stock:not-a-uuid") == nil)
    }

    @Test
    func stack_encodes_members_as_stable_tokens() throws {
        let id = UUID()
        let customID = UUID()
        let stockID = UUID()
        let stack = TouchBarStack(
            id: id,
            members: [.metric(.cpu), .customMetric(customID), .stock(stockID)]
        )
        let data = try JSONEncoder().encode(stack)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["id"] as? String == id.uuidString)
        #expect(object["members"] as? [String] == [
            "metric:cpu",
            "custom:\(customID.uuidString)",
            "stock:\(stockID.uuidString)",
        ])
        #expect(try JSONDecoder().decode(TouchBarStack.self, from: data) == stack)
    }

    @Test
    func stack_decode_drops_unreadable_members_instead_of_failing() throws {
        let json = """
        {"id":"\(UUID().uuidString)","members":["metric:cpu","bogus","stock:not-a-uuid"]}
        """
        let stack = try JSONDecoder().decode(TouchBarStack.self, from: Data(json.utf8))
        #expect(stack.members == [.metric(.cpu)])
    }

    @Test
    func stack_decode_without_an_id_generates_one() throws {
        let stack = try JSONDecoder().decode(
            TouchBarStack.self,
            from: Data(#"{"members":["metric:cpu"]}"#.utf8)
        )
        #expect(stack.members == [.metric(.cpu)])
    }

    @Test
    func configuration_decode_without_stacks_yields_empty_list() throws {
        let json = """
        {"mode":"alwaysExpanded"}
        """
        let configuration = try JSONDecoder().decode(TouchBarConfiguration.self, from: Data(json.utf8))
        #expect(configuration.stacks.isEmpty)
    }

    @Test
    func configuration_roundtrips_stacks() throws {
        let stack = TouchBarStack(members: [.metric(.storage), .metric(.keyboardBattery)])
        let configuration = TouchBarConfiguration(
            mode: .smart,
            excludedBundleIdentifiers: [],
            stacks: [stack]
        )
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(TouchBarConfiguration.self, from: data)
        #expect(decoded == configuration)
    }

    @Test
    func normalization_drops_duplicates_empty_stacks_cross_group_members_and_excess() {
        let stockID = UUID()
        let first = TouchBarStack(members: [.metric(.cpu), .metric(.memory)])
        let second = TouchBarStack(members: [.metric(.memory), .metric(.storage), .stock(stockID)])
        let normalized = TouchBarConfiguration.normalizedStacks([
            first,
            TouchBarStack(members: []),
            second,
            TouchBarStack(members: [.metric(.battery)]),
            TouchBarStack(members: [.metric(.network)]),
            TouchBarStack(members: [.metric(.fan)]),
        ])
        #expect(normalized.count == TouchBarConfiguration.maxStacks)
        #expect(normalized[0].members == [.metric(.cpu), .metric(.memory)])
        // The repeated memory member and the stock (wrong group) are dropped.
        #expect(normalized[1].members == [.metric(.storage)])
        #expect(normalized[2].members == [.metric(.battery)])
        #expect(normalized[3].members == [.metric(.network)])
        #expect(normalized.allSatisfy { !$0.members.isEmpty })
    }

    @Test
    func assign_builds_a_stack_then_moves_members_out() {
        var configuration = TouchBarConfiguration.default
        configuration.assign(.metric(.storage), to: .newStack)
        configuration.assign(.metric(.keyboardBattery), to: .stack(configuration.stacks[0].id))
        #expect(configuration.stacks.count == 1)
        #expect(configuration.stacks[0].members == [.metric(.storage), .metric(.keyboardBattery)])

        configuration.assign(.metric(.storage), to: .independent)
        #expect(configuration.stacks[0].members == [.metric(.keyboardBattery)])

        configuration.assign(.metric(.keyboardBattery), to: .independent)
        #expect(configuration.stacks.isEmpty)
    }

    @Test
    func assign_keeps_stocks_out_of_metric_stacks() {
        var configuration = TouchBarConfiguration.default
        configuration.assign(.metric(.cpu), to: .newStack)
        let metricStackID = configuration.stacks[0].id
        let stockID = UUID()

        configuration.assign(.stock(stockID), to: .stack(metricStackID))
        #expect(configuration.stacks.count == 1)
        #expect(configuration.stacks[0].members == [.metric(.cpu)])

        configuration.assign(.stock(stockID), to: .newStack)
        #expect(configuration.stacks.count == 2)
        #expect(configuration.stacks[1].members == [.stock(stockID)])
    }

    @Test
    func assign_stops_at_the_stack_cap() {
        var configuration = TouchBarConfiguration.default
        for metric in [TouchBarMetric.cpu, .memory, .storage, .battery, .network] {
            configuration.assign(.metric(metric), to: .newStack)
        }
        #expect(configuration.stacks.count == TouchBarConfiguration.maxStacks)
        // The item that could not get a new stack stays unassigned.
        #expect(configuration.stack(containing: .metric(.network)) == nil)
    }
}
