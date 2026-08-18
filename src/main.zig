// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const practice = @import("pr_practice");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const command = if (args.len > 1) args[1] else "home";
    if (std.mem.eql(u8, command, "home") or std.mem.eql(u8, command, "run")) {
        showHome();
        return;
    }
    if (std.mem.eql(u8, command, "golden")) {
        const runs = [_]practice.GoldenRun{
            .corrected_launch_standard,
            .staged_launch_standard,
            .pause_and_replan_alternative,
            .invented_endorsement_critical,
        };
        for (runs) |run| showOutcome(try practice.runGolden(run));
        return;
    }
    if (std.mem.eql(u8, command, "demo")) {
        const route = if (args.len > 2) args[2] else "corrected";
        const run: practice.GoldenRun = if (std.mem.eql(u8, route, "staged"))
            .staged_launch_standard
        else if (std.mem.eql(u8, route, "pause"))
            .pause_and_replan_alternative
        else if (std.mem.eql(u8, route, "critical"))
            .invented_endorsement_critical
        else
            .corrected_launch_standard;
        showOutcome(try practice.runGolden(run));
        return;
    }
    std.debug.print("Unknown command: {s}\nUse: home | demo [corrected|staged|pause|critical] | golden\n", .{command});
    std.process.exit(2);
}

fn showHome() void {
    std.debug.print(
        \\{s}
        \\
        \\PR Practice Lab — Phase A local practice shell
        \\Scenario: Northstar Mobility Pilot Launch ({s}@{s})
        \\Reference pack: {s} — PROVISIONAL/UNREVIEWED
        \\
        \\Commands:
        \\  zig build run -- demo corrected
        \\  zig build run -- demo staged
        \\  zig build run -- demo pause
        \\  zig build run -- demo critical
        \\  zig build run -- golden
        \\
        \\The deterministic slice records brief clarification, evidence requests,
        \\uncertainty, stakeholders, objectives and measures, declared AI use,
        \\drafting, verification, accessibility, approval, enquiry handling,
        \\plural route choice, campaign consequences and assessed practice.
        \\
    , .{ practice.watermark, practice.scenario_id, practice.scenario_version, practice.rule_pack });
}

fn showOutcome(outcome: practice.GoldenOutcome) void {
    const digest = std.fmt.bytesToHex(outcome.digest, .lower);
    std.debug.print(
        "run={s} route={s} threshold={} critical={} events={d} reach={d} trust={d} integrity={d} accessibility={d} registrations={d} elapsed={d} digest={s}\n",
        .{
            @tagName(outcome.run),
            @tagName(outcome.route),
            outcome.result.threshold(),
            outcome.result.critical_error,
            outcome.event_count,
            outcome.campaign.relevant_reach,
            outcome.campaign.stakeholder_trust,
            outcome.campaign.factual_integrity,
            outcome.campaign.accessibility,
            outcome.campaign.registrations,
            outcome.campaign.elapsed_minutes,
            &digest,
        },
    );
}
