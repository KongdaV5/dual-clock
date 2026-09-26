#import <Cocoa/Cocoa.h>
#import <math.h>

#pragma mark - Helpers

static NSCalendar *CNCalendar(void) {
    static NSCalendar *cal = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        cal.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        cal.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        cal.firstWeekday = 2;
    });
    return cal;
}

static NSCalendar *ChineseCalendar(void) {
    static NSCalendar *cal = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierChinese];
        cal.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    });
    return cal;
}

static NSCalendar *UTCCalendar(void) {
    static NSCalendar *cal = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });
    return cal;
}

static NSDateFormatter *ISODateFormatter(void) {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        fmt.dateFormat = @"yyyy-MM-dd";
    });
    return fmt;
}

static NSString *DateKey(NSDate *date) {
    return [ISODateFormatter() stringFromDate:date];
}

static NSDate *DateFromKey(NSString *key) {
    return [ISODateFormatter() dateFromString:key];
}

static NSDate *StartOfCNDay(NSDate *date) {
    return [CNCalendar() startOfDayForDate:date];
}

static NSInteger DaysBetween(NSDate *a, NSDate *b) {
    NSDate *sa = StartOfCNDay(a);
    NSDate *sb = StartOfCNDay(b);
    NSDateComponents *c = [CNCalendar() components:NSCalendarUnitDay fromDate:sa toDate:sb options:0];
    return c.day;
}

static void DrawText(NSString *text, NSRect rect, NSFont *font, NSColor *color, NSTextAlignment align) {
    if (!text) return;
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = align;
    ps.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: ps
    };
    [text drawInRect:rect withAttributes:attrs];
}

static void DrawCenteredText(NSString *text, NSRect rect, NSFont *font, NSColor *color) {
    if (!text) return;
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color
    };
    NSSize size = [text sizeWithAttributes:attrs];
    NSPoint point = NSMakePoint(NSMidX(rect) - size.width / 2.0,
                                NSMidY(rect) - size.height / 2.0);
    [text drawAtPoint:point withAttributes:attrs];
}

static void FillRounded(NSRect rect, CGFloat radius, NSColor *color) {
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
}

static NSColor *PanelBG(void) {
    return NSColor.windowBackgroundColor;
}

static const CGFloat kPanelWidth = 336.0;
static const CGFloat kHeaderHeight = 61.0;
static const CGFloat kWeekdayHeight = 22.0;
static const CGFloat kCalendarTop = 83.0;
static const CGFloat kCalendarRowHeight = 42.0;
static const CGFloat kGridInsetX = 8.0;
static const CGFloat kCalendarBottomPad = 8.0;
static const CGFloat kGoalHeaderHeight = 35.0;
static const CGFloat kFooterHeight = 29.0;

#pragma mark - Holiday store

@interface HolidayStore : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *byDate;
@property(nonatomic, strong) NSArray<NSString *> *sortedKeys;
- (NSDictionary *)holidayForDate:(NSDate *)date;
- (NSDictionary *)nextHolidayFrom:(NSDate *)date;
@end

@implementation HolidayStore

- (instancetype)init {
    self = [super init];
    if (self) {
        _byDate = [NSMutableDictionary dictionary];
        [self loadBundledYears];
    }
    return self;
}

- (void)loadBundledYears {
    NSBundle *bundle = [NSBundle mainBundle];
    NSArray<NSString *> *years = @[@"2025", @"2026"];
    for (NSString *year in years) {
        NSString *path = [bundle pathForResource:year ofType:@"json" inDirectory:@"holidays"];
        if (!path) continue;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *days = obj[@"days"];
        if (![days isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *d in days) {
            NSString *key = d[@"date"];
            if (![key isKindOfClass:[NSString class]]) continue;
            self.byDate[key] = @{
                @"name": d[@"name"] ?: @"节假日",
                @"isOffDay": d[@"isOffDay"] ?: @NO
            };
        }
    }
    self.sortedKeys = [[self.byDate allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSDictionary *)holidayForDate:(NSDate *)date {
    return self.byDate[DateKey(date)];
}

- (NSDictionary *)nextHolidayFrom:(NSDate *)date {
    NSDate *today = StartOfCNDay(date);
    for (NSString *key in self.sortedKeys) {
        NSDate *d = DateFromKey(key);
        if (!d || [d compare:today] == NSOrderedAscending) continue;

        NSDictionary *h = self.byDate[key];
        if (![h[@"isOffDay"] boolValue]) continue;

        NSString *name = h[@"name"] ?: @"节假日";
        NSDate *prev = [CNCalendar() dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:d options:0];
        NSDictionary *prevH = self.byDate[DateKey(prev)];
        if (prevH && [prevH[@"isOffDay"] boolValue] && [prevH[@"name"] isEqualToString:name]) continue;

        return @{@"date": d, @"name": name};
    }
    return nil;
}
@end

#pragma mark - Lunar / festival helpers

static NSString *LunarDayName(NSInteger day) {
    static NSArray<NSString *> *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[@"", @"初一",@"初二",@"初三",@"初四",@"初五",@"初六",@"初七",@"初八",@"初九",@"初十",
                  @"十一",@"十二",@"十三",@"十四",@"十五",@"十六",@"十七",@"十八",@"十九",@"二十",
                  @"廿一",@"廿二",@"廿三",@"廿四",@"廿五",@"廿六",@"廿七",@"廿八",@"廿九",@"三十"];
    });
    if (day >= 1 && day < (NSInteger)names.count) return names[day];
    return @"";
}

static NSString *LunarMonthName(NSInteger month) {
    static NSArray<NSString *> *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[@"", @"正月",@"二月",@"三月",@"四月",@"五月",@"六月",
                  @"七月",@"八月",@"九月",@"十月",@"冬月",@"腊月"];
    });
    if (month >= 1 && month < (NSInteger)names.count) return names[month];
    return @"";
}

static NSString *TraditionalFestival(NSInteger month, NSInteger day) {
    if (month == 1 && day == 1) return @"春节";
    if (month == 1 && day == 15) return @"元宵";
    if (month == 5 && day == 5) return @"端午";
    if (month == 7 && day == 7) return @"七夕";
    if (month == 8 && day == 15) return @"中秋";
    if (month == 9 && day == 9) return @"重阳";
    if (month == 12 && day == 8) return @"腊八";
    return nil;
}

static NSDictionary<NSString *, NSString *> *SolarTermsForYear(NSInteger year) {
    static NSMutableDictionary<NSNumber *, NSDictionary<NSString *, NSString *> *> *cache = nil;
    static NSArray<NSString *> *names = nil;
    static NSArray<NSNumber *> *mins = nil;
    static NSDate *baseDate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
        names = @[@"小寒",@"大寒",@"立春",@"雨水",@"惊蛰",@"春分",@"清明",@"谷雨",
                  @"立夏",@"小满",@"芒种",@"夏至",@"小暑",@"大暑",@"立秋",@"处暑",
                  @"白露",@"秋分",@"寒露",@"霜降",@"立冬",@"小雪",@"大雪",@"冬至"];
        mins = @[@0,@21208,@42467,@63836,@85337,@107014,@128867,@150921,
                 @173149,@195551,@218072,@240693,@263343,@285989,@308563,@331033,
                 @353350,@375494,@397447,@419210,@440795,@462224,@483532,@504758];

        NSDateComponents *baseC = [NSDateComponents new];
        baseC.year = 1900;
        baseC.month = 1;
        baseC.day = 6;
        baseC.hour = 2;
        baseC.minute = 5;
        baseDate = [UTCCalendar() dateFromComponents:baseC];
    });

    if (year < 1900 || year > 2100) return @{};

    NSNumber *key = @(year);
    NSDictionary *cached = cache[key];
    if (cached) return cached;

    NSMutableDictionary<NSString *, NSString *> *terms = [NSMutableDictionary dictionaryWithCapacity:24];
    for (NSInteger i = 0; i < 24; i++) {
        NSTimeInterval seconds = 31556925.9747 * (year - 1900) + mins[i].doubleValue * 60.0;
        NSDate *termDate = [baseDate dateByAddingTimeInterval:seconds];
        terms[DateKey(termDate)] = names[i];
    }
    NSDictionary *result = [terms copy];
    cache[key] = result;
    return result;
}

static NSString *SolarTermForDate(NSDate *date) {
    NSInteger year = [CNCalendar() component:NSCalendarUnitYear fromDate:date];
    return SolarTermsForYear(year)[DateKey(date)];
}

static NSString *SolarFestival(NSDate *date) {
    NSDateComponents *c = [CNCalendar() components:(NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitWeekday) fromDate:date];
    if (c.month == 1 && c.day == 1) return @"元旦";
    if (c.month == 5 && c.day == 1) return @"劳动节";
    if (c.month == 6 && c.day == 1) return @"儿童节";
    if (c.month == 10 && c.day == 1) return @"国庆";
    if (c.month == 5 && c.weekday == 1 && c.day >= 8 && c.day <= 14) return @"母亲节";
    if (c.month == 6 && c.weekday == 1 && c.day >= 15 && c.day <= 21) return @"父亲节";
    return nil;
}

static NSString *CalendarSubLabel(NSDate *date) {
    NSDateComponents *lunar = [ChineseCalendar() components:(NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:date];

    NSString *festival = TraditionalFestival(lunar.month, lunar.day);
    if (festival) return festival;

    NSString *solarFestival = SolarFestival(date);
    if (solarFestival) return solarFestival;

    NSString *term = SolarTermForDate(date);
    if (term) return term;

    if (lunar.day == 1) return LunarMonthName(lunar.month);
    return LunarDayName(lunar.day);
}

#pragma mark - Goal store

@interface GoalStore : NSObject
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *goals;
- (void)reload;
- (void)save;
@end

@implementation GoalStore
- (instancetype)init {
    self = [super init];
    if (self) [self reload];
    return self;
}
- (void)sortGoals {
    [self.goals sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"end"] compare:b[@"end"]];
    }];
}
- (void)reload {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:@"DualClockGoalsV1"];
    _goals = [NSMutableArray array];
    for (NSDictionary *d in stored ?: @[]) [_goals addObject:[d mutableCopy]];
    [self sortGoals];
}
- (void)save {
    [self sortGoals];
    [[NSUserDefaults standardUserDefaults] setObject:self.goals forKey:@"DualClockGoalsV1"];
}
@end

@class CalendarPanelView;

@protocol CalendarPanelDelegate <NSObject>
- (void)calendarPanelRequestAddGoal:(CalendarPanelView *)panel;
- (void)calendarPanel:(CalendarPanelView *)panel requestEditGoalAtIndex:(NSInteger)index;
- (void)calendarPanel:(CalendarPanelView *)panel requestDeleteGoalAtIndex:(NSInteger)index;
- (void)calendarPanelDidChangeHeight:(CalendarPanelView *)panel;
- (void)calendarPanelRequestQuit:(CalendarPanelView *)panel;
@end

#pragma mark - Calendar panel

@interface CalendarPanelView : NSView
@property(nonatomic, weak) id<CalendarPanelDelegate> delegate;
@property(nonatomic, strong) HolidayStore *holidayStore;
@property(nonatomic, strong) GoalStore *goalStore;
@property(nonatomic) NSInteger displayYear;
@property(nonatomic) NSInteger displayMonth;
@property(nonatomic) BOOL goalsCollapsed;
@property(nonatomic, strong) NSMutableArray<NSValue *> *editRects;
@property(nonatomic, strong) NSMutableArray<NSValue *> *deleteRects;
- (CGFloat)preferredHeight;
- (void)goToday;
@end

@implementation CalendarPanelView {
    NSRect _prevRect, _todayRect, _nextRect, _goalsHeaderRect, _addGoalRect, _quitRect;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _holidayStore = [HolidayStore new];
        _goalStore = [GoalStore new];
        _editRects = [NSMutableArray array];
        _deleteRects = [NSMutableArray array];

        NSDateComponents *c = [CNCalendar() components:(NSCalendarUnitYear|NSCalendarUnitMonth) fromDate:[NSDate date]];
        _displayYear = c.year;
        _displayMonth = c.month;

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:@"DualClockGoalsCollapsed"] == nil) {
            _goalsCollapsed = YES;
        } else {
            _goalsCollapsed = [ud boolForKey:@"DualClockGoalsCollapsed"];
        }
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (CGFloat)calendarBottom {
    return kHeaderHeight + kWeekdayHeight + 6.0 * kCalendarRowHeight + kCalendarBottomPad;
}

- (CGFloat)preferredHeight {
    CGFloat h = [self calendarBottom] + kGoalHeaderHeight + kFooterHeight;
    if (!self.goalsCollapsed) {
        NSInteger count = MIN((NSInteger)self.goalStore.goals.count, 5);
        h += count * 70 + (self.goalStore.goals.count > 5 ? 21 : 0) + 6;
    }
    return h;
}

- (NSDate *)dateForYear:(NSInteger)year month:(NSInteger)month day:(NSInteger)day {
    NSDateComponents *c = [NSDateComponents new];
    c.year = year; c.month = month; c.day = day; c.hour = 12;
    return [CNCalendar() dateFromComponents:c];
}

- (NSString *)monthTitle {
    return [NSString stringWithFormat:@"%ld月", (long)self.displayMonth];
}

- (NSString *)nextHolidayPill {
    NSDictionary *h = [self.holidayStore nextHolidayFrom:[NSDate date]];
    if (!h) return nil;
    NSInteger days = DaysBetween([NSDate date], h[@"date"]);
    NSString *name = h[@"name"] ?: @"节假日";
    if (days == 0) return [NSString stringWithFormat:@"%@ 今天", name];
    return [NSString stringWithFormat:@"%@ %ld天后", name, (long)days];
}

- (void)drawHeader {
    CGFloat w = NSWidth(self.bounds);
    NSColor *label = NSColor.labelColor;
    NSColor *secondary = NSColor.secondaryLabelColor;
    NSColor *accent = NSColor.controlAccentColor;

    DrawText([self monthTitle], NSMakeRect(16, 10, 74, 40),
             [NSFont systemFontOfSize:27 weight:NSFontWeightBold], label, NSTextAlignmentLeft);
    DrawText([NSString stringWithFormat:@"%ld", (long)self.displayYear], NSMakeRect(82, 22, 50, 22),
             [NSFont systemFontOfSize:14.5 weight:NSFontWeightSemibold], secondary, NSTextAlignmentLeft);

    NSString *pill = [self nextHolidayPill];
    if (pill.length) {
        NSFont *font = [NSFont systemFontOfSize:9.5 weight:NSFontWeightMedium];
        CGFloat pw = MIN(102, [pill sizeWithAttributes:@{NSFontAttributeName:font}].width + 14);
        NSRect pr = NSMakeRect(130, 22, pw, 20);
        FillRounded(pr, 10, [accent colorWithAlphaComponent:0.12]);
        DrawText(pill, NSInsetRect(pr, 4, 3), font, accent, NSTextAlignmentCenter);
    }

    CGFloat navX = w - 106;
    NSRect navBG = NSMakeRect(navX, 17, 90, 26);
    FillRounded(navBG, 13, [NSColor quaternaryLabelColor]);

    _prevRect = NSMakeRect(navX, 17, 28, 26);
    _todayRect = NSMakeRect(navX + 28, 17, 35, 26);
    _nextRect = NSMakeRect(navX + 63, 17, 27, 26);
    DrawCenteredText(@"‹", _prevRect, [NSFont systemFontOfSize:19 weight:NSFontWeightRegular], label);
    DrawCenteredText(@"今", _todayRect, [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold], label);
    DrawCenteredText(@"›", _nextRect, [NSFont systemFontOfSize:19 weight:NSFontWeightRegular], label);
}

- (void)drawWeekdays {
    NSArray *days = @[@"一",@"二",@"三",@"四",@"五",@"六",@"日"];
    CGFloat gridW = NSWidth(self.bounds) - 2.0 * kGridInsetX;
    CGFloat cellW = gridW / 7.0;
    for (NSInteger i = 0; i < 7; i++) {
        NSColor *c = (i >= 5) ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
        DrawText(days[i], NSMakeRect(kGridInsetX + i * cellW, kHeaderHeight, cellW, kWeekdayHeight),
                 [NSFont systemFontOfSize:9.8 weight:NSFontWeightSemibold], c, NSTextAlignmentCenter);
    }
}

- (void)drawCalendar {
    NSCalendar *cal = CNCalendar();
    NSDate *first = [self dateForYear:self.displayYear month:self.displayMonth day:1];
    NSDateComponents *fc = [cal components:NSCalendarUnitWeekday fromDate:first];
    NSInteger offset = (fc.weekday + 5) % 7;
    NSInteger daysInMonth = [cal rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:first].length;

    CGFloat gridW = NSWidth(self.bounds) - 2.0 * kGridInsetX;
    CGFloat cellW = gridW / 7.0;
    CGFloat top = kCalendarTop;
    CGFloat cellH = kCalendarRowHeight;

    NSDateComponents *todayC = [cal components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:[NSDate date]];

    for (NSInteger day = 1; day <= daysInMonth; day++) {
        NSInteger idx = offset + day - 1;
        NSInteger row = idx / 7;
        NSInteger col = idx % 7;

        NSRect cell = NSMakeRect(kGridInsetX + col * cellW + 2.5,
                                 top + row * cellH + 1.5,
                                 cellW - 5.0,
                                 cellH - 3.0);
        NSDate *date = [self dateForYear:self.displayYear month:self.displayMonth day:day];

        NSDictionary *holiday = [self.holidayStore holidayForDate:date];
        BOOL isOff = holiday && [holiday[@"isOffDay"] boolValue];
        BOOL isMakeup = holiday && ![holiday[@"isOffDay"] boolValue];
        BOOL weekend = (col >= 5);
        BOOL isToday = (todayC.year == self.displayYear && todayC.month == self.displayMonth && todayC.day == day);

        NSColor *numColor = NSColor.labelColor;
        NSColor *subColor = NSColor.secondaryLabelColor;
        if (weekend) numColor = NSColor.controlAccentColor;

        if (isOff && !isToday) {
            FillRounded(cell, 8, [NSColor.controlAccentColor colorWithAlphaComponent:0.12]);
            numColor = NSColor.controlAccentColor;
        }
        if (isMakeup && !isToday) {
            FillRounded(cell, 8, [[NSColor systemOrangeColor] colorWithAlphaComponent:0.10]);
            numColor = NSColor.labelColor;
        }
        if (isToday) {
            FillRounded(cell, 8, NSColor.controlAccentColor);
            numColor = NSColor.whiteColor;
            subColor = [NSColor.whiteColor colorWithAlphaComponent:0.85];
        }

        DrawText([NSString stringWithFormat:@"%ld", (long)day],
                 NSMakeRect(NSMinX(cell)+3, NSMinY(cell)+4, NSWidth(cell)-6, 18),
                 [NSFont monospacedDigitSystemFontOfSize:14.5 weight:NSFontWeightSemibold],
                 numColor, NSTextAlignmentCenter);

        NSString *sub = CalendarSubLabel(date);
        DrawText(sub, NSMakeRect(NSMinX(cell)+2, NSMinY(cell)+23, NSWidth(cell)-4, 14),
                 [NSFont systemFontOfSize:8.5 weight:NSFontWeightMedium],
                 subColor, NSTextAlignmentCenter);

        if (isOff || isMakeup) {
            NSString *badge = isOff ? @"休" : @"班";
            NSColor *badgeColor = isOff ? NSColor.controlAccentColor : NSColor.systemOrangeColor;
            NSRect br = NSMakeRect(NSMaxX(cell)-14.5, NSMinY(cell)-1.5, 14.5, 14.5);
            FillRounded(br, 7.25, badgeColor);
            NSFont *badgeFont = [NSFont systemFontOfSize:7.2 weight:NSFontWeightBold];
            NSDictionary *badgeAttrs = @{
                NSFontAttributeName: badgeFont,
                NSForegroundColorAttributeName: NSColor.whiteColor
            };
            NSSize badgeSize = [badge sizeWithAttributes:badgeAttrs];
            NSPoint badgePoint = NSMakePoint(NSMidX(br) - badgeSize.width / 2.0,
                                             NSMidY(br) - badgeSize.height / 2.0);
            [badge drawAtPoint:badgePoint withAttributes:badgeAttrs];
        }
    }
}

- (NSDictionary *)goalStats:(NSDictionary *)goal {
    NSDate *start = DateFromKey(goal[@"start"]);
    NSDate *end = DateFromKey(goal[@"end"]);
    NSDate *today = StartOfCNDay([NSDate date]);
    if (!start || !end) return @{@"progress":@0, @"status":@"日期无效"};

    NSInteger total = MAX(1, DaysBetween(start, end));
    NSInteger elapsed = DaysBetween(start, today);
    CGFloat p = MIN(1.0, MAX(0.0, (CGFloat)elapsed / (CGFloat)total));

    NSString *status = nil;
    if ([today compare:start] == NSOrderedAscending) {
        status = [NSString stringWithFormat:@"还有 %ld 天开始", (long)DaysBetween(today, start)];
    } else if ([today compare:end] == NSOrderedDescending) {
        status = [NSString stringWithFormat:@"已到目标日 %ld 天", (long)DaysBetween(end, today)];
        p = 1.0;
    } else {
        NSInteger left = MAX(0, DaysBetween(today, end));
        status = [NSString stringWithFormat:@"剩余 %ld 天 · %ld%%", (long)left, (long)llround(p*100)];
    }
    return @{@"progress":@(p), @"status":status};
}

- (void)drawGoals {
    [self.editRects removeAllObjects];
    [self.deleteRects removeAllObjects];

    CGFloat y = [self calendarBottom];
    CGFloat w = NSWidth(self.bounds);

    [[NSColor.separatorColor colorWithAlphaComponent:0.55] setFill];
    NSRectFill(NSMakeRect(0, y, w, 1));

    _goalsHeaderRect = NSMakeRect(0, y+1, w, 33);
    NSString *chev = self.goalsCollapsed ? @"▸" : @"▾";
    DrawText([NSString stringWithFormat:@"%@  我的目标", chev], NSMakeRect(14, y+9, 130, 18),
             [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold], NSColor.labelColor, NSTextAlignmentLeft);

    NSString *count = [NSString stringWithFormat:@"%ld", (long)self.goalStore.goals.count];
    DrawText(count, NSMakeRect(w-61, y+9, 20, 18),
             [NSFont monospacedDigitSystemFontOfSize:9.6 weight:NSFontWeightMedium],
             NSColor.secondaryLabelColor, NSTextAlignmentRight);

    _addGoalRect = NSMakeRect(w-40, y+4, 30, 26);
    DrawText(@"＋", _addGoalRect, [NSFont systemFontOfSize:16 weight:NSFontWeightRegular],
             NSColor.controlAccentColor, NSTextAlignmentCenter);

    y += 36;

    if (!self.goalsCollapsed) {
        NSInteger visible = MIN((NSInteger)self.goalStore.goals.count, 5);
        for (NSInteger i=0; i<visible; i++) {
            NSDictionary *g = self.goalStore.goals[i];
            NSRect card = NSMakeRect(10, y, w-20, 64);
            FillRounded(card, 10, [NSColor.controlBackgroundColor colorWithAlphaComponent:0.90]);

            NSString *name = g[@"name"] ?: @"未命名目标";
            DrawText(name, NSMakeRect(NSMinX(card)+11, NSMinY(card)+7, NSWidth(card)-82, 18),
                     [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold], NSColor.labelColor, NSTextAlignmentLeft);

            NSString *range = [NSString stringWithFormat:@"%@ → %@", g[@"start"] ?: @"", g[@"end"] ?: @""];
            DrawText(range, NSMakeRect(NSMinX(card)+11, NSMinY(card)+24, NSWidth(card)-22, 14),
                     [NSFont monospacedDigitSystemFontOfSize:8.4 weight:NSFontWeightRegular],
                     NSColor.secondaryLabelColor, NSTextAlignmentLeft);

            NSString *note = g[@"note"] ?: @"";
            if (note.length) {
                DrawText(note, NSMakeRect(NSMinX(card)+11, NSMinY(card)+39, NSWidth(card)-94, 13),
                         [NSFont systemFontOfSize:8.4 weight:NSFontWeightRegular],
                         NSColor.secondaryLabelColor, NSTextAlignmentLeft);
            }

            NSDictionary *stats = [self goalStats:g];
            CGFloat p = [stats[@"progress"] doubleValue];
            NSRect track = NSMakeRect(NSMinX(card)+11, NSMaxY(card)-8, NSWidth(card)-90, 3);
            FillRounded(track, 1.5, [NSColor.quaternaryLabelColor colorWithAlphaComponent:0.55]);
            NSRect fill = track;
            fill.size.width = MAX(2, track.size.width * p);
            FillRounded(fill, 1.5, NSColor.controlAccentColor);

            DrawText(stats[@"status"], NSMakeRect(NSMaxX(card)-78, NSMinY(card)+27, 66, 18),
                     [NSFont systemFontOfSize:8 weight:NSFontWeightMedium],
                     NSColor.secondaryLabelColor, NSTextAlignmentRight);

            NSRect edit = NSMakeRect(NSMaxX(card)-71, NSMinY(card)+6, 34, 17);
            NSRect del = NSMakeRect(NSMaxX(card)-35, NSMinY(card)+6, 24, 17);
            DrawText(@"编辑", edit, [NSFont systemFontOfSize:8.4 weight:NSFontWeightMedium],
                     NSColor.controlAccentColor, NSTextAlignmentCenter);
            DrawText(@"删除", del, [NSFont systemFontOfSize:8.4 weight:NSFontWeightMedium],
                     NSColor.systemRedColor, NSTextAlignmentCenter);
            [self.editRects addObject:[NSValue valueWithRect:edit]];
            [self.deleteRects addObject:[NSValue valueWithRect:del]];
            y += 70;
        }

        if (self.goalStore.goals.count > 5) {
            DrawText([NSString stringWithFormat:@"另有 %ld 个目标未展开显示", (long)(self.goalStore.goals.count-5)],
                     NSMakeRect(14, y, w-28, 18),
                     [NSFont systemFontOfSize:8.4], NSColor.secondaryLabelColor, NSTextAlignmentCenter);
            y += 21;
        }
        y += 3;
    }

    _quitRect = NSMakeRect(w-56, [self preferredHeight]-25, 42, 18);
    DrawText(@"退出", _quitRect, [NSFont systemFontOfSize:9.2 weight:NSFontWeightMedium],
             NSColor.secondaryLabelColor, NSTextAlignmentRight);
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [PanelBG() setFill];
    NSRectFill(self.bounds);
    [self drawHeader];
    [self drawWeekdays];
    [self drawCalendar];
    [self drawGoals];
}

- (void)changeMonth:(NSInteger)delta {
    NSInteger m = self.displayMonth + delta;
    NSInteger y = self.displayYear;
    if (m < 1) { m = 12; y--; }
    if (m > 12) { m = 1; y++; }
    self.displayMonth = m;
    self.displayYear = y;
    [self setNeedsDisplay:YES];
}

- (void)goToday {
    NSDateComponents *c = [CNCalendar() components:(NSCalendarUnitYear|NSCalendarUnitMonth) fromDate:[NSDate date]];
    self.displayYear = c.year;
    self.displayMonth = c.month;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];

    if (NSPointInRect(p, _prevRect)) { [self changeMonth:-1]; return; }
    if (NSPointInRect(p, _todayRect)) { [self goToday]; return; }
    if (NSPointInRect(p, _nextRect)) { [self changeMonth:1]; return; }

    if (NSPointInRect(p, _addGoalRect)) {
        [self.delegate calendarPanelRequestAddGoal:self];
        return;
    }

    if (NSPointInRect(p, _goalsHeaderRect)) {
        self.goalsCollapsed = !self.goalsCollapsed;
        [[NSUserDefaults standardUserDefaults] setBool:self.goalsCollapsed forKey:@"DualClockGoalsCollapsed"];
        [self.delegate calendarPanelDidChangeHeight:self];
        return;
    }

    for (NSInteger i=0; i<(NSInteger)self.editRects.count; i++) {
        if (NSPointInRect(p, self.editRects[i].rectValue)) {
            [self.delegate calendarPanel:self requestEditGoalAtIndex:i];
            return;
        }
    }
    for (NSInteger i=0; i<(NSInteger)self.deleteRects.count; i++) {
        if (NSPointInRect(p, self.deleteRects[i].rectValue)) {
            [self.delegate calendarPanel:self requestDeleteGoalAtIndex:i];
            return;
        }
    }

    if (NSPointInRect(p, _quitRect)) {
        [self.delegate calendarPanelRequestQuit:self];
        return;
    }
}
@end

#pragma mark - Popover controller

@interface CalendarPopoverController : NSViewController <CalendarPanelDelegate>
@property(nonatomic, strong) CalendarPanelView *panel;
@property(nonatomic, weak) NSPopover *popover;
- (void)resizeToPanel;
@end

@implementation CalendarPopoverController

- (void)loadView {
    self.panel = [[CalendarPanelView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 400)];
    self.panel.delegate = self;
    self.view = self.panel;
    [self resizeToPanel];
}

- (void)resizeToPanel {
    CGFloat h = [self.panel preferredHeight];
    self.panel.frame = NSMakeRect(0, 0, kPanelWidth, h);
    self.preferredContentSize = NSMakeSize(kPanelWidth, h);
    if (self.popover) self.popover.contentSize = NSMakeSize(kPanelWidth, h);
    [self.panel setNeedsDisplay:YES];
}

- (NSDictionary *)runGoalEditorWithGoal:(NSDictionary *)goal {
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [NSAlert new];
    alert.messageText = goal ? @"编辑目标" : @"添加目标";
    alert.informativeText = @"目标数据只保存在本机。";
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];

    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 172)];

    NSTextField *nameLabel = [NSTextField labelWithString:@"名称"];
    nameLabel.frame = NSMakeRect(0, 143, 46, 20);
    NSTextField *name = [NSTextField textFieldWithString:goal[@"name"] ?: @""];
    name.placeholderString = @"例如：完成某项长期目标";
    name.frame = NSMakeRect(52, 141, 264, 23);

    NSTextField *startLabel = [NSTextField labelWithString:@"开始"];
    startLabel.frame = NSMakeRect(0, 108, 46, 20);
    NSDatePicker *start = [[NSDatePicker alloc] initWithFrame:NSMakeRect(52, 105, 174, 24)];
    start.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    start.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    start.dateValue = goal ? (DateFromKey(goal[@"start"]) ?: [NSDate date]) : [NSDate date];

    NSTextField *endLabel = [NSTextField labelWithString:@"目标日"];
    endLabel.frame = NSMakeRect(0, 73, 46, 20);
    NSDatePicker *end = [[NSDatePicker alloc] initWithFrame:NSMakeRect(52, 70, 174, 24)];
    end.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    end.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    end.dateValue = goal ? (DateFromKey(goal[@"end"]) ?: [NSDate date]) :
        [CNCalendar() dateByAddingUnit:NSCalendarUnitDay value:30 toDate:[NSDate date] options:0];

    NSTextField *noteLabel = [NSTextField labelWithString:@"备注"];
    noteLabel.frame = NSMakeRect(0, 38, 46, 20);
    NSTextField *note = [NSTextField textFieldWithString:goal[@"note"] ?: @""];
    note.placeholderString = @"例如：每日两次 / 项目说明 / 阶段目标";
    note.frame = NSMakeRect(52, 36, 264, 23);

    [box addSubview:nameLabel]; [box addSubview:name];
    [box addSubview:startLabel]; [box addSubview:start];
    [box addSubview:endLabel]; [box addSubview:end];
    [box addSubview:noteLabel]; [box addSubview:note];
    alert.accessoryView = box;

    NSModalResponse r = [alert runModal];
    if (r != NSAlertFirstButtonReturn) return nil;

    NSString *trim = [name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trim.length == 0) {
        NSBeep();
        return nil;
    }
    NSDate *sd = StartOfCNDay(start.dateValue);
    NSDate *ed = StartOfCNDay(end.dateValue);
    if ([ed compare:sd] == NSOrderedAscending) {
        NSAlert *bad = [NSAlert new];
        bad.messageText = @"目标日期不能早于开始日期";
        [bad addButtonWithTitle:@"好"];
        [bad runModal];
        return nil;
    }

    return @{
        @"name": trim,
        @"start": DateKey(sd),
        @"end": DateKey(ed),
        @"note": note.stringValue ?: @""
    };
}

- (void)calendarPanelRequestAddGoal:(CalendarPanelView *)panel {
    NSDictionary *newGoal = [self runGoalEditorWithGoal:nil];
    if (!newGoal) return;
    [self.panel.goalStore.goals addObject:[newGoal mutableCopy]];
    [self.panel.goalStore save];
    self.panel.goalsCollapsed = NO;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"DualClockGoalsCollapsed"];
    [self resizeToPanel];
}

- (void)calendarPanel:(CalendarPanelView *)panel requestEditGoalAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.panel.goalStore.goals.count) return;
    NSDictionary *old = self.panel.goalStore.goals[index];
    NSDictionary *updated = [self runGoalEditorWithGoal:old];
    if (!updated) return;
    self.panel.goalStore.goals[index] = [updated mutableCopy];
    [self.panel.goalStore save];
    [self resizeToPanel];
}

- (void)calendarPanel:(CalendarPanelView *)panel requestDeleteGoalAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.panel.goalStore.goals.count) return;
    NSDictionary *goal = self.panel.goalStore.goals[index];

    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *a = [NSAlert new];
    a.messageText = [NSString stringWithFormat:@"删除“%@”？", goal[@"name"] ?: @"这个目标"];
    a.informativeText = @"删除后无法恢复。";
    [a addButtonWithTitle:@"删除"];
    [a addButtonWithTitle:@"取消"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;

    [self.panel.goalStore.goals removeObjectAtIndex:index];
    [self.panel.goalStore save];
    [self resizeToPanel];
}

- (void)calendarPanelDidChangeHeight:(CalendarPanelView *)panel {
    [self resizeToPanel];
}

- (void)calendarPanelRequestQuit:(CalendarPanelView *)panel {
    [NSApp terminate:nil];
}
@end

#pragma mark - Two-line status item

@interface ClockView : NSView
@property(nonatomic, copy) NSString *topText;
@property(nonatomic, copy) NSString *bottomText;
- (CGFloat)measuredWidth;
@end

@implementation ClockView {
    NSFont *_font;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) _font = [NSFont monospacedDigitSystemFontOfSize:9.5 weight:NSFontWeightRegular];
    return self;
}
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)p { return nil; }
- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByClipping;
    NSDictionary *a = @{NSFontAttributeName:_font,
                        NSForegroundColorAttributeName:NSColor.labelColor,
                        NSParagraphStyleAttributeName:ps};
    CGFloat lh = 10.8, y = MAX(0, (NSHeight(self.bounds)-lh*2)/2);
    [self.topText drawInRect:NSMakeRect(0,y-0.2,NSWidth(self.bounds),lh+1) withAttributes:a];
    [self.bottomText drawInRect:NSMakeRect(0,y+lh-0.2,NSWidth(self.bounds),lh+1) withAttributes:a];
}
- (CGFloat)measuredWidth {
    NSDictionary *a = @{NSFontAttributeName:_font};
    CGFloat w1 = [self.topText sizeWithAttributes:a].width;
    CGFloat w2 = [self.bottomText sizeWithAttributes:a].width;
    return ceil(MAX(w1,w2)+10);
}
@end

#pragma mark - App delegate

@interface AppDelegate : NSObject <NSApplicationDelegate, NSPopoverDelegate>
@end

@implementation AppDelegate {
    NSStatusItem *_item;
    ClockView *_clockView;
    NSTimer *_timer;
    NSDateFormatter *_cn;
    NSDateFormatter *_pt;
    NSPopover *_popover;
    CalendarPopoverController *_calendarController;
    id _localMouseMonitor;
    id _globalMouseMonitor;
    NSTimer *_popoverCloseTimer;
    NSString *_lastCalendarDayKey;
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    _cn = [NSDateFormatter new];
    _cn.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    _cn.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    _cn.dateFormat = @"M.d EEE HH:mm:ss";

    _pt = [NSDateFormatter new];
    _pt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    _pt.timeZone = [NSTimeZone timeZoneWithName:@"America/Los_Angeles"];
    _pt.dateFormat = @"M.d EEE HH:mm:ss";

    _item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = _item.button;
    button.title = @"";
    button.image = nil;
    button.target = self;
    button.action = @selector(togglePopover:);
    [button sendActionOn:NSEventMaskLeftMouseDown];

    _clockView = [[ClockView alloc] initWithFrame:button.bounds];
    _clockView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [button addSubview:_clockView];

    [self tick:nil];
    [self scheduleAlignedClockTimer];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(systemTimeDidChange:)
                                                 name:NSSystemClockDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(systemTimeDidChange:)
                                                 name:NSSystemTimeZoneDidChangeNotification
                                               object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                            selector:@selector(workspaceDidWake:)
                                                                name:NSWorkspaceDidWakeNotification
                                                              object:nil];

    [self ensureCalendarPopover];
    [_calendarController loadView];
}

- (void)scheduleAlignedClockTimer {
    [_timer invalidate];
    _timer = nil;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval nextWholeSecond = floor(now) + 1.0;
    NSDate *fireDate = [NSDate dateWithTimeIntervalSince1970:nextWholeSecond];

    _timer = [[NSTimer alloc] initWithFireDate:fireDate
                                      interval:1.0
                                        target:self
                                      selector:@selector(tick:)
                                      userInfo:nil
                                       repeats:YES];
    _timer.tolerance = 0.0;
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)resyncClockAndCalendar {
    [self tick:nil];
    [self scheduleAlignedClockTimer];
    if (_calendarController.panel) {
        [_calendarController.panel goToday];
    }
}

- (void)systemTimeDidChange:(NSNotification *)notification {
    (void)notification;
    [self resyncClockAndCalendar];
}

- (void)workspaceDidWake:(NSNotification *)notification {
    (void)notification;
    [self resyncClockAndCalendar];
}

- (NSString *)compactWeekday:(NSString *)s {
    return [s stringByReplacingOccurrencesOfString:@"周" withString:@""];
}

- (void)tick:(id)sender {
    (void)sender;
    NSDate *now = [NSDate date];
    NSString *cnText = [self compactWeekday:[_cn stringFromDate:now]];
    NSString *ptText = [self compactWeekday:[_pt stringFromDate:now]];
    _clockView.topText = [@"CN " stringByAppendingString:cnText];
    _clockView.bottomText = [@"PT " stringByAppendingString:ptText];
    _item.length = [_clockView measuredWidth];
    [_clockView setNeedsDisplay:YES];

    NSString *dayKey = DateKey(now);
    BOOL dayChanged = (_lastCalendarDayKey != nil && ![_lastCalendarDayKey isEqualToString:dayKey]);
    _lastCalendarDayKey = dayKey;
    if (dayChanged && _calendarController.panel) {
        [_calendarController.panel goToday];
    }
}

- (void)ensureCalendarPopover {
    if (_popover) return;

    _calendarController = [CalendarPopoverController new];
    _popover = [NSPopover new];
    _popover.behavior = NSPopoverBehaviorTransient;
    _popover.animates = NO;
    _popover.delegate = self;
    _popover.contentViewController = _calendarController;
    _calendarController.popover = _popover;
}

- (NSRect)statusButtonScreenRect {
    NSStatusBarButton *button = _item.button;
    if (!button.window) return NSZeroRect;

    NSRect windowRect = [button convertRect:button.bounds toView:nil];
    return [button.window convertRectToScreen:windowRect];
}

- (BOOL)pointerIsOverPopoverOrStatusButton {
    NSPoint pointer = NSEvent.mouseLocation;

    NSWindow *popoverWindow = _popover.contentViewController.view.window;
    if (popoverWindow && NSPointInRect(pointer, NSInsetRect(popoverWindow.frame, -3.0, -3.0))) {
        return YES;
    }

    NSRect statusRect = [self statusButtonScreenRect];
    return !NSIsEmptyRect(statusRect) && NSPointInRect(pointer, NSInsetRect(statusRect, -3.0, -3.0));
}

- (void)cancelScheduledPopoverClose {
    [_popoverCloseTimer invalidate];
    _popoverCloseTimer = nil;
}

- (void)stopPointerMonitoring {
    [self cancelScheduledPopoverClose];

    if (_localMouseMonitor) {
        [NSEvent removeMonitor:_localMouseMonitor];
        _localMouseMonitor = nil;
    }
    if (_globalMouseMonitor) {
        [NSEvent removeMonitor:_globalMouseMonitor];
        _globalMouseMonitor = nil;
    }
}

- (void)closePopoverIfPointerStillOutside:(NSTimer *)timer {
    _popoverCloseTimer = nil;
    if (_popover.shown && ![self pointerIsOverPopoverOrStatusButton]) {
        [_popover performClose:nil];
    }
}

- (void)pointerDidMove {
    if (!_popover.shown) {
        [self stopPointerMonitoring];
        return;
    }

    if ([self pointerIsOverPopoverOrStatusButton]) {
        [self cancelScheduledPopoverClose];
        return;
    }
    if (_popoverCloseTimer) return;

    _popoverCloseTimer = [NSTimer timerWithTimeInterval:0.22
                                                  target:self
                                                selector:@selector(closePopoverIfPointerStillOutside:)
                                                userInfo:nil
                                                 repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:_popoverCloseTimer forMode:NSRunLoopCommonModes];
}

- (void)startPointerMonitoring {
    [self stopPointerMonitoring];

    NSEventMask movementMask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged |
                              NSEventMaskRightMouseDragged | NSEventMaskOtherMouseDragged;
    __weak AppDelegate *weakSelf = self;
    _localMouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:movementMask handler:^NSEvent * _Nullable(NSEvent *event) {
        [weakSelf pointerDidMove];
        return event;
    }];
    _globalMouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:movementMask handler:^(NSEvent *event) {
        (void)event;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf pointerDidMove];
        });
    }];
}

- (void)togglePopover:(id)sender {
    if (_popover.shown) {
        [_popover performClose:nil];
        return;
    }

    [self ensureCalendarPopover];
    [_calendarController.panel goToday];

    [_popover showRelativeToRect:_item.button.bounds
                         ofView:_item.button
                  preferredEdge:NSRectEdgeMinY];
    [self startPointerMonitoring];
}

- (void)popoverDidClose:(NSNotification *)notification {
    [self stopPointerMonitoring];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self stopPointerMonitoring];
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
