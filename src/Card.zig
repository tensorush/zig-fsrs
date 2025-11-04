//! Flashcard for review scheduling based on the FSRS-6 algorithm.

const std = @import("std");
const zdt = @import("zdt");

const Card = @This();

state: State,
stability: f64,
difficulty: f64,
next_datetime: zdt.Datetime,
prev_datetime_opt: ?zdt.Datetime,

const MIN_STABILITY = 1e-3;
const MIN_DIFFICULTY = 1.0;
const MAX_DIFFICULTY = 10.0;
const DECAY = -PARAMETERS[20];
const DESIRED_RETENTION = 0.9;
const MAX_DAY_INTERVAL = 36500;
const TOLERANCE = std.math.floatEps(f32);
const FACTOR = std.math.pow(f64, 0.9, 1.0 / DECAY) - 1.0;
const INIT_INTERVAL: zdt.Duration = .fromTimespanMultiple(10, .minute);
const PARAMETERS = [21]f64{ 0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542 };

pub const State = enum {
    Learning,
    Review,
};

pub const Rating = enum {
    Again,
    Hard,
    Good,
    Easy,
};

/// Create a card with the initial rating.
pub fn init(rating: Rating) Card {
    return .{
        .state = .Learning,
        .stability = PARAMETERS[@intFromEnum(rating)],
        .difficulty = initialDifficulty(rating, true),
        .next_datetime = undefined,
        .prev_datetime_opt = null,
    };
}

/// Review the card with the given rating at the given time.
pub fn review(
    card: *Card,
    rating: Card.Rating,
    datetime: zdt.Datetime,
) zdt.ZdtError!void {
    const is_short_term = if (card.prev_datetime_opt) |prev_datetime| datetime.diff(prev_datetime).totalDays() < 1.0 else true;

    card.stability = if (is_short_term)
        shortTermStability(card.stability, rating)
    else
        longTermStability(card.difficulty, card.stability, card.getRetrievability(datetime), rating);
    card.difficulty = nextDifficulty(card.difficulty, rating);

    const next_interval: zdt.Duration = blk: switch (card.state) {
        .Learning => switch (rating) {
            .Again => INIT_INTERVAL,
            .Hard,
            .Good,
            .Easy,
            => {
                card.state = .Review;
                break :blk nextInterval(card.stability);
            },
        },
        .Review => switch (rating) {
            .Again => {
                card.state = .Learning;
                break :blk INIT_INTERVAL;
            },
            .Hard,
            .Good,
            .Easy,
            => nextInterval(card.stability),
        },
    };

    card.next_datetime = try datetime.add(next_interval);
    card.prev_datetime_opt = datetime;
}

fn getRetrievability(card: *const Card, datetime: zdt.Datetime) f64 {
    return if (card.prev_datetime_opt) |prev_datetime|
        std.math.pow(f64, 1.0 + FACTOR * @max(0.0, datetime.diff(prev_datetime).totalDays()) / card.stability, DECAY)
    else
        0.0;
}

fn clampStability(stability: f64) f64 {
    return @max(stability, MIN_STABILITY);
}

fn clampDifficulty(difficulty: f64) f64 {
    return @min(@max(difficulty, MIN_DIFFICULTY), MAX_DIFFICULTY);
}

fn initialDifficulty(rating: Card.Rating, with_clamp: bool) f64 {
    var initial_difficulty = PARAMETERS[4] - std.math.pow(f64, std.math.e, PARAMETERS[5] * @as(f64, @floatFromInt(@intFromEnum(rating)))) + 1.0;
    if (with_clamp) initial_difficulty = clampDifficulty(initial_difficulty);
    return initial_difficulty;
}

fn nextDifficulty(difficulty: f64, rating: Card.Rating) f64 {
    return clampDifficulty(PARAMETERS[7] * initialDifficulty(.Easy, false) +
        (1.0 - PARAMETERS[7]) * (difficulty + (10.0 - difficulty) * (-PARAMETERS[6] * @as(f64, @floatFromInt(@as(i3, @intCast(@intFromEnum(rating))) - 2))) / 9.0));
}

fn nextInterval(stability: f64) zdt.Duration {
    var next_interval: i64 = @intFromFloat(@round((stability / FACTOR) * (std.math.pow(f64, DESIRED_RETENTION, 1.0 / DECAY) - 1.0)));
    next_interval = @max(next_interval, 1);
    next_interval = @min(next_interval, MAX_DAY_INTERVAL);
    return .fromTimespanMultiple(next_interval, .day);
}

fn shortTermStability(stability: f64, rating: Card.Rating) f64 {
    var short_term_stability_increase =
        std.math.pow(f64, std.math.e, PARAMETERS[17] * (@as(f64, @floatFromInt(@as(i3, @intCast(@intFromEnum(rating))) - 2)) + PARAMETERS[18])) *
        std.math.pow(f64, stability, -PARAMETERS[19]);
    if (rating == .Good or rating == .Easy) {
        short_term_stability_increase = @max(short_term_stability_increase, 1.0);
    }
    return clampStability(stability * short_term_stability_increase);
}

fn longTermStability(difficulty: f64, stability: f64, retrievability: f64, rating: Card.Rating) f64 {
    return clampStability(if (rating == .Again)
        @min(stability, PARAMETERS[11] *
            std.math.pow(f64, difficulty, -PARAMETERS[12]) *
            (std.math.pow(f64, stability + 1.0, PARAMETERS[13]) - 1.0) *
            std.math.pow(f64, std.math.e, (1.0 - retrievability) * PARAMETERS[14]))
    else
        stability * (1.0 + std.math.pow(f64, std.math.e, PARAMETERS[8]) *
            (11.0 - difficulty) *
            std.math.pow(f64, stability, -PARAMETERS[9]) *
            (std.math.pow(f64, std.math.e, (1.0 - retrievability) * PARAMETERS[10]) - 1.0) *
            if (rating == .Hard) PARAMETERS[15] else 1.0 * if (rating == .Easy) PARAMETERS[16] else 1.0));
}

test getRetrievability {
    var card: Card = .init(.Good);
    try std.testing.expectEqual(.Learning, card.state);
    try std.testing.expectEqual(0.0, card.getRetrievability(.nowUTC()));

    try std.testing.expectEqual(.Learning, card.state);
    try std.testing.expectEqual(0.0, card.getRetrievability(.nowUTC()));

    try card.review(.Good, .nowUTC());
    try std.testing.expectEqual(.Review, card.state);
    try std.testing.expectApproxEqAbs(1.0, card.getRetrievability(.nowUTC()), TOLERANCE);

    try card.review(.Good, .nowUTC());
    try std.testing.expectEqual(.Review, card.state);
    try std.testing.expectApproxEqAbs(1.0, card.getRetrievability(.nowUTC()), TOLERANCE);

    try card.review(.Again, .nowUTC());
    try std.testing.expectEqual(.Learning, card.state);
    try std.testing.expectApproxEqAbs(1.0, card.getRetrievability(.nowUTC()), TOLERANCE);
}

test review {
    const RATINGS = [_]Card.Rating{ .Good, .Good, .Good, .Good, .Good, .Good, .Again, .Again, .Good, .Good, .Good, .Good, .Good };
    const EXPECTED_DAY_INTERVALS: [RATINGS.len]usize = .{ 2, 11, 46, 163, 498, 1348, 0, 0, 3, 5, 9, 16, 26 };

    var card: Card = .init(RATINGS[0]);
    var datetime: zdt.Datetime = .nowUTC();
    inline for (RATINGS, EXPECTED_DAY_INTERVALS) |RATING, EXPECTED_DAY_INTERVAL| {
        try card.review(RATING, datetime);
        try std.testing.expectEqual(EXPECTED_DAY_INTERVAL, @as(usize, @intFromFloat(card.next_datetime.diff(card.prev_datetime_opt.?).totalDays())));
        datetime = card.next_datetime;
    }
}
