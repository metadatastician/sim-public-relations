// SPDX-License-Identifier: MPL-2.0
const std = @import("std");

pub const scenario_id = "northstar-mobility-001";
pub const scenario_version = "0.1.0";
pub const rule_pack = "uk-pr-practice-provisional@0.1.0";
pub const watermark = "FICTIONAL SIMULATION — NOT LIVE CLIENT WORK OR EMPLOYMENT EXPERIENCE";
pub const max_events = 128;
pub const max_note = 120;
pub const zero_digest = [_]u8{0} ** 32;

pub const Route = enum { undecided, proceed_with_corrections, stage_the_launch, pause_and_replan };

pub const EventKind = enum(u16) {
    session_started,
    brief_clarified,
    evidence_requested,
    evidence_disclosed,
    uncertainty_recorded,
    stakeholders_mapped,
    objectives_planned,
    ai_use_declared,
    artefact_drafted,
    claim_verified,
    accessibility_checked,
    approval_requested,
    approval_recorded,
    enquiry_received,
    enquiry_responded,
    route_considered,
    route_selected,
    critical_error_recorded,
    assessment_submitted,
};

pub const Event = struct {
    sequence: u16,
    kind: EventKind,
    logical_minute: u32,
    note_len: u8,
    note: [max_note]u8,
    previous_digest: [32]u8,
    digest: [32]u8,

    pub fn noteSlice(self: *const Event) []const u8 {
        return self.note[0..self.note_len];
    }
};

pub const Ledger = struct {
    events: [max_events]Event = undefined,
    len: usize = 0,

    pub fn append(self: *Ledger, kind: EventKind, minute: u32, note_text: []const u8) !void {
        if (self.len >= max_events) return error.LedgerFull;
        if (note_text.len > max_note) return error.NoteTooLong;
        const previous = if (self.len == 0) zero_digest else self.events[self.len - 1].digest;
        var event: Event = .{
            .sequence = @intCast(self.len),
            .kind = kind,
            .logical_minute = minute,
            .note_len = @intCast(note_text.len),
            .note = [_]u8{0} ** max_note,
            .previous_digest = previous,
            .digest = undefined,
        };
        @memcpy(event.note[0..note_text.len], note_text);
        event.digest = digestEvent(&event);
        self.events[self.len] = event;
        self.len += 1;
    }

    pub fn headDigest(self: *const Ledger) [32]u8 {
        return if (self.len == 0) zero_digest else self.events[self.len - 1].digest;
    }

    pub fn verify(self: *const Ledger) bool {
        var previous = zero_digest;
        for (self.events[0..self.len], 0..) |event, index| {
            if (event.sequence != index) return false;
            if (!std.mem.eql(u8, &event.previous_digest, &previous)) return false;
            if (!std.mem.eql(u8, &event.digest, &digestEvent(&event))) return false;
            previous = event.digest;
        }
        return true;
    }
};

fn digestEvent(event: *const Event) [32]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(&event.previous_digest);
    hash.update(std.mem.asBytes(&event.sequence));
    const kind: u16 = @intFromEnum(event.kind);
    hash.update(std.mem.asBytes(&kind));
    hash.update(std.mem.asBytes(&event.logical_minute));
    hash.update(event.noteSlice());
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}

pub const CompetencyResult = struct {
    brief: u8 = 0,
    research: u8 = 0,
    claims: u8 = 0,
    stakeholders: u8 = 0,
    planning: u8 = 0,
    editorial: u8 = 0,
    coordination: u8 = 0,
    measurement: u8 = 0,
    ethics: u8 = 0,
    ai_accountability: u8 = 0,
    critical_error: bool = false,

    pub fn threshold(self: CompetencyResult) bool {
        return !self.critical_error and self.brief >= 2 and self.research >= 2 and
            self.claims >= 2 and self.stakeholders >= 2 and self.planning >= 2 and
            self.editorial >= 2 and self.coordination >= 2 and self.measurement >= 2 and
            self.ethics >= 2 and self.ai_accountability >= 2;
    }
};

pub const CampaignOutcome = struct {
    relevant_reach: i16 = 50,
    stakeholder_trust: i16 = 50,
    factual_integrity: i16 = 50,
    accessibility: i16 = 50,
    registrations: i16 = 0,
    elapsed_minutes: u32 = 0,
};

pub const Session = struct {
    logical_minute: u32 = 0,
    resource_units: i16 = 100,
    evidence_count: u8 = 6,
    uncertainties: u8 = 0,
    routes_considered: u8 = 0,
    route: Route = .undecided,
    brief_clear: bool = false,
    stakeholders_ready: bool = false,
    plan_ready: bool = false,
    ai_declared: bool = false,
    artefact_ready: bool = false,
    claims_verified: bool = false,
    accessibility_checked: bool = false,
    approval_recorded: bool = false,
    enquiry_handled: bool = false,
    fabricated_endorsement: bool = false,
    submitted: bool = false,
    ledger: Ledger = .{},
    outcome: CampaignOutcome = .{},

    pub fn init() !Session {
        var self: Session = .{};
        try self.record(.session_started, "role=junior-account-practitioner;initial-disclosures=6");
        return self;
    }

    fn record(self: *Session, kind: EventKind, note: []const u8) !void {
        try self.ledger.append(kind, self.logical_minute, note);
    }

    fn spend(self: *Session, minutes: u32, units: i16) !void {
        if (self.submitted) return error.AlreadySubmitted;
        if (self.resource_units < units) return error.ResourceInsufficient;
        self.logical_minute += minutes;
        self.resource_units -= units;
        self.outcome.elapsed_minutes = self.logical_minute;
    }

    pub fn clarifyBrief(self: *Session) !void {
        try self.spend(20, 4);
        self.brief_clear = true;
        try self.record(.brief_clarified, "purpose;scope;deadline;approval;ai-policy;unknowns");
    }

    pub fn requestEvidence(self: *Session, request: []const u8) !void {
        try self.spend(30, 8);
        try self.record(.evidence_requested, request);
        if (std.mem.eql(u8, request, "claim-substantiation") or
            std.mem.eql(u8, request, "accessibility-evidence") or
            std.mem.eql(u8, request, "brief-and-approval-context") or
            std.mem.eql(u8, request, "measurement-baseline"))
        {
            self.evidence_count += 1;
            try self.record(.evidence_disclosed, "bounded-source-disclosed;interpretation-required");
        } else {
            try self.record(.evidence_disclosed, "no-additional-record-within-scenario");
        }
    }

    pub fn recordUncertainty(self: *Session, note: []const u8) !void {
        if (self.submitted or note.len == 0) return error.InvalidCommand;
        self.uncertainties += 1;
        try self.record(.uncertainty_recorded, note);
    }

    pub fn mapStakeholders(self: *Session) !void {
        if (!self.brief_clear) return error.PrerequisiteMissing;
        try self.spend(35, 8);
        self.stakeholders_ready = true;
        try self.record(.stakeholders_mapped, "affected;audience;interest;access;relationship-context");
    }

    pub fn planObjectives(self: *Session) !void {
        if (!self.brief_clear or !self.stakeholders_ready or self.evidence_count < 8)
            return error.PrerequisiteMissing;
        try self.spend(40, 10);
        self.plan_ready = true;
        try self.record(.objectives_planned, "objective;baseline;output;outtake;outcome;limits");
    }

    pub fn declareAIUse(self: *Session) !void {
        if (self.submitted) return error.AlreadySubmitted;
        self.ai_declared = true;
        try self.record(.ai_use_declared, "ideation-and-variants;no-contact-data;human-verification");
    }

    pub fn draftArtefact(self: *Session) !void {
        if (!self.plan_ready) return error.PrerequisiteMissing;
        try self.spend(45, 10);
        self.artefact_ready = true;
        try self.record(.artefact_drafted, "announcement;targeted-pitch;accessible-summary;version=1");
    }

    pub fn verifyClaims(self: *Session) !void {
        if (!self.artefact_ready or self.evidence_count < 9) return error.PrerequisiteMissing;
        try self.spend(25, 6);
        self.claims_verified = true;
        self.outcome.factual_integrity += 20;
        try self.record(.claim_verified, "material-claims-linked;unsupported-wording-narrowed");
    }

    pub fn checkAccessibility(self: *Session) !void {
        if (!self.artefact_ready) return error.PrerequisiteMissing;
        try self.spend(20, 5);
        self.accessibility_checked = true;
        self.outcome.accessibility += 20;
        try self.record(.accessibility_checked, "format;language;contact-route;claim-scope");
    }

    pub fn recordApproval(self: *Session) !void {
        if (!self.claims_verified or !self.accessibility_checked) return error.PrerequisiteMissing;
        try self.spend(20, 4);
        try self.record(.approval_requested, "agency-lead;client-lead;specialist-owner");
        self.approval_recorded = true;
        try self.record(.approval_recorded, "verified-core-only;unresolved-elements-held");
    }

    pub fn handleEnquiry(self: *Session) !void {
        if (self.logical_minute < 180) try self.spend(180 - self.logical_minute, 0);
        try self.record(.enquiry_received, "fictional-journalist;date-and-access-questions");
        if (!self.brief_clear) return error.PrerequisiteMissing;
        try self.spend(25, 6);
        self.enquiry_handled = true;
        self.outcome.stakeholder_trust += if (self.claims_verified) 15 else -15;
        try self.record(.enquiry_responded, "acknowledged;verified-answer;uncertainty-and-next-update");
    }

    pub fn considerRoute(self: *Session, route: Route) !void {
        if (route == .undecided) return error.InvalidCommand;
        self.routes_considered += 1;
        try self.record(.route_considered, @tagName(route));
    }

    pub fn selectRoute(self: *Session, route: Route) !void {
        if (self.routes_considered < 2 or !self.enquiry_handled) return error.PrerequisiteMissing;
        self.route = route;
        switch (route) {
            .proceed_with_corrections => {
                if (!self.approval_recorded) return error.PrerequisiteMissing;
                self.outcome.relevant_reach += 25;
                self.outcome.registrations += 12;
            },
            .stage_the_launch => {
                self.outcome.relevant_reach += 10;
                self.outcome.stakeholder_trust += 10;
                self.outcome.registrations += 4;
            },
            .pause_and_replan => {
                self.outcome.relevant_reach -= 15;
                self.outcome.stakeholder_trust += 20;
            },
            .undecided => unreachable,
        }
        try self.record(.route_selected, @tagName(route));
    }

    pub fn fabricateEndorsement(self: *Session) !void {
        if (!self.artefact_ready) return error.PrerequisiteMissing;
        self.fabricated_endorsement = true;
        self.outcome.relevant_reach += 40;
        self.outcome.registrations += 20;
        self.outcome.factual_integrity -= 45;
        self.outcome.stakeholder_trust -= 35;
        try self.record(.critical_error_recorded, "invented-endorsement;polished-output-does-not-cure");
    }

    pub fn assess(self: *const Session) CompetencyResult {
        const research_score: u8 = if (self.evidence_count >= 10) 3 else if (self.evidence_count >= 8) 2 else 1;
        const claims_score: u8 = if (self.claims_verified) 3 else if (self.uncertainties > 0) 2 else 1;
        const coordination_score: u8 = if (self.approval_recorded and self.enquiry_handled) 3 else if (self.enquiry_handled) 2 else 1;
        return .{
            .brief = if (self.brief_clear) 3 else 1,
            .research = research_score,
            .claims = claims_score,
            .stakeholders = if (self.stakeholders_ready) 3 else 1,
            .planning = if (self.plan_ready) 3 else 1,
            .editorial = if (self.artefact_ready and self.claims_verified and self.accessibility_checked) 3 else if (self.artefact_ready) 2 else 1,
            .coordination = coordination_score,
            .measurement = if (self.plan_ready and self.evidence_count >= 10) 3 else if (self.plan_ready) 2 else 1,
            .ethics = if (self.fabricated_endorsement) 0 else if (self.claims_verified and self.route != .undecided) 3 else 2,
            .ai_accountability = if (self.ai_declared and self.claims_verified) 3 else if (self.claims_verified) 2 else 1,
            .critical_error = self.fabricated_endorsement,
        };
    }

    pub fn submit(self: *Session) !CompetencyResult {
        if (self.route == .undecided or !self.ledger.verify()) return error.PrerequisiteMissing;
        self.submitted = true;
        try self.record(.assessment_submitted, "competency-and-outcome-reported-separately");
        return self.assess();
    }
};

pub const GoldenRun = enum {
    corrected_launch_standard,
    staged_launch_standard,
    pause_and_replan_alternative,
    invented_endorsement_critical,
};

pub const GoldenOutcome = struct {
    run: GoldenRun,
    route: Route,
    result: CompetencyResult,
    campaign: CampaignOutcome,
    event_count: usize,
    digest: [32]u8,
};

pub fn runGolden(run: GoldenRun) !GoldenOutcome {
    var session = try Session.init();
    try session.clarifyBrief();
    try session.requestEvidence("brief-and-approval-context");
    try session.requestEvidence("claim-substantiation");
    try session.requestEvidence("accessibility-evidence");
    try session.requestEvidence("measurement-baseline");
    try session.recordUncertainty("launch-date;approval;claim-scope;stakeholder-response");
    try session.mapStakeholders();
    try session.planObjectives();
    try session.declareAIUse();
    try session.draftArtefact();
    try session.verifyClaims();
    try session.checkAccessibility();
    try session.recordApproval();
    try session.handleEnquiry();
    try session.considerRoute(.proceed_with_corrections);
    try session.considerRoute(.stage_the_launch);
    try session.considerRoute(.pause_and_replan);

    const route: Route = switch (run) {
        .corrected_launch_standard, .invented_endorsement_critical => .proceed_with_corrections,
        .staged_launch_standard => .stage_the_launch,
        .pause_and_replan_alternative => .pause_and_replan,
    };
    if (run == .invented_endorsement_critical) try session.fabricateEndorsement();
    try session.selectRoute(route);
    const result = try session.submit();
    return .{
        .run = run,
        .route = route,
        .result = result,
        .campaign = session.outcome,
        .event_count = session.ledger.len,
        .digest = session.ledger.headDigest(),
    };
}

test "event ledger detects tampering" {
    var session = try Session.init();
    try session.clarifyBrief();
    try std.testing.expect(session.ledger.verify());
    session.ledger.events[1].note[0] = 'X';
    try std.testing.expect(!session.ledger.verify());
}

test "plural routes can demonstrate the same threshold" {
    const corrected = try runGolden(.corrected_launch_standard);
    const staged = try runGolden(.staged_launch_standard);
    const paused = try runGolden(.pause_and_replan_alternative);
    try std.testing.expect(corrected.result.threshold());
    try std.testing.expect(staged.result.threshold());
    try std.testing.expect(paused.result.threshold());
    try std.testing.expect(corrected.campaign.relevant_reach > paused.campaign.relevant_reach);
    try std.testing.expect(paused.campaign.stakeholder_trust > corrected.campaign.stakeholder_trust);
}

test "attractive output cannot average away a critical error" {
    const standard = try runGolden(.corrected_launch_standard);
    const critical = try runGolden(.invented_endorsement_critical);
    try std.testing.expect(critical.campaign.relevant_reach > standard.campaign.relevant_reach);
    try std.testing.expect(critical.result.critical_error);
    try std.testing.expect(!critical.result.threshold());
}

test "golden runs are deterministic" {
    const first = try runGolden(.staged_launch_standard);
    const second = try runGolden(.staged_launch_standard);
    try std.testing.expectEqualSlices(u8, &first.digest, &second.digest);
    try std.testing.expectEqual(first.event_count, second.event_count);
}
