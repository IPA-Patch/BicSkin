// BicSkin — ポイントカード画像をダブルタップで default / Bicame Musume に切り替える
// logos の %hook を使わず objc runtime API で method swizzle。これで
// Sideload IPA (Dobby 静的) では CydiaSubstrate 依存が入らない。
//
// 切り替えは常に「BicCamera bundled default (pointcard_default) ↔ Bicame Musume」
// の 2 択固定。account が既に Bicame Musume を所有していても toggle が意味を持つ
// ように、原本画像には依存しない。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Bicame Musume (ビッカメ娘) カード絵柄。本来この絵柄はそのカードを所有する
// アカウントにしか表示されないが、BicCamera の CDN 上に公開されているので
// URL を直接叩いて取得できる。
static NSString *const kBicSkinBicameMusumeURL =
    @"https://d1v4cay8lxkuwy.cloudfront.net/?storagekey=/images/pointCard/bicamemusume.png";
static UIImage *g_bicame_image = nil;

// default (plain "BicCamera POINT CARD" watermark) は BicCamera の app bundle 内
// asset `pointcard_default` から imageNamed で引く。lazy 読み込み。
static UIImage *g_default_image = nil;

// トグル状態 (NO = default 表示、YES = Bicame Musume 表示)。
// UserDefaults に永続化して、次回起動時にも同じ側を初期表示する。
static NSString *const kBicSkinShowBicameKey = @"__BicSkin_showBicame__";
static BOOL g_show_bicame = NO;

// ---------------------------------------------------------------------------
// ファイルログ (Documents/bicskin.log)
// ---------------------------------------------------------------------------
static NSString *g_logPath = nil;

static void ensure_log_path(void) {
    if (g_logPath) return;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count == 0) return;
    g_logPath = [[paths firstObject] stringByAppendingPathComponent:@"bicskin.log"];
}

static void bic_log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void bic_log(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSLog(@"[BicSkin] %@", msg);

    ensure_log_path();
    if (!g_logPath) return;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                      [NSDate date].description, msg];
    FILE *f = fopen(g_logPath.UTF8String, "a");
    if (f) {
        fputs(line.UTF8String, f);
        fclose(f);
    }
}

// ---------------------------------------------------------------------------
// DEBUG ビルド専用: ポイントカードレスポンスをダミー値で上書き
//   機能説明スクショで実値を晒さないためのもの。FINALPACKAGE=1 で消える。
// ---------------------------------------------------------------------------
#ifdef DEBUG
static NSString * const kDummyBarcode          = @"3141592653589";
static const long long kDummyCardNumber        = 31415926535LL;
static NSString * const kDummyPointExpiration  = @"2038-01-19";  // Y2K38
static NSString * const kDummyBicpayExpiration = @"2077-01-01";  // 目印用

static id bic_skin_apply(id obj) {
    if (![obj isKindOfClass:[NSDictionary class]]) return obj;
    NSDictionary *dict = (NSDictionary *)obj;
    if (dict[@"pointCardNumber"] == nil && dict[@"barcodeNumber"] == nil) {
        return obj;
    }
    NSMutableDictionary *m =
        [dict isKindOfClass:[NSMutableDictionary class]]
            ? (NSMutableDictionary *)dict
            : [dict mutableCopy];
    m[@"barcodeNumber"]   = kDummyBarcode;
    m[@"pointCardNumber"] = @(kDummyCardNumber);
    m[@"points"]          = @0;
    m[@"bicpayPoints"]    = @0;
    if (m[@"pointExpiration"])
        m[@"pointExpiration"] = kDummyPointExpiration;
    if (m[@"bicpayPointExpiration"])
        m[@"bicpayPointExpiration"] = kDummyBicpayExpiration;
    bic_log(@"[DEBUG] tampering applied to keys=%@",
            [dict.allKeys componentsJoinedByString:@","]);
    return m;
}
#endif

// 与えられた UIImageView が PointCard 系のセル配下に居るか判定。
// setImage の時点で view が hierarchy に載っていれば class 名で当てられる。
static BOOL bic_is_point_card_view(UIImageView *iv) {
    for (UIView *v = iv.superview; v; v = v.superview) {
        if ([NSStringFromClass([v class]) containsString:@"PointCard"]) {
            return YES;
        }
    }
    return NO;
}

// iv を含む枝を深さ優先で辿り、最深の cornerRadius > 0 の view を返す。
static UIView *bic_deepest_rounded_containing(UIView *root, UIView *iv) {
    UIView *best = (root.layer.cornerRadius > 0 && [iv isDescendantOfView:root])
                   ? root : nil;
    for (UIView *sub in root.subviews) {
        if (![iv isDescendantOfView:sub]) continue;
        UIView *cand = bic_deepest_rounded_containing(sub, iv);
        if (cand) best = cand;
    }
    return best;
}

// ---------------------------------------------------------------------------
// UIImageView category (setImage: swizzle + double-tap action)
// ---------------------------------------------------------------------------
@interface UIImageView (BicSkin)
- (void)bicSkin_setImage:(UIImage *)image;
- (void)bicSkin_doubleTap:(UITapGestureRecognizer *)gr;
@end

@implementation UIImageView (BicSkin)

// 自分自身の呼び出しは swizzle 後に元の setImage: の実装に飛ぶ (%orig と同等)。
// PointCard 判定できる時のみ image を UserDefaults 由来の側 (default / Bicame
// Musume) に差し替えて呼び直す。判定に失敗するタイミング (setImage が view
// hierarchy 挿入前に呼ばれるケース等) では原本のまま通す。
- (void)bicSkin_setImage:(UIImage *)image {
    UIImage *toSet = image;
    if (image && image.CGImage && bic_is_point_card_view(self) &&
        g_default_image && g_bicame_image) {
        toSet = g_show_bicame ? g_bicame_image : g_default_image;
    }
    [self bicSkin_setImage:toSet];

    if (!image) return;
    CGImageRef cg = image.CGImage;
    if (!cg) return;
    size_t w = CGImageGetWidth(cg);
    size_t h = CGImageGetHeight(cg);
    if (w * h < 100000) return;

    // default 画像 lazy load。asset catalog が ready な大画像 setImage で。
    if (!g_default_image) {
        g_default_image = [UIImage imageNamed:@"pointcard_default"];
        if (g_default_image) {
            bic_log(@"default image loaded (imageNamed:pointcard_default)");
        }
    }

    // ダブルタップ gesture を 1 回だけ install (大画像全般)
    NSNumber *installed = objc_getAssociatedObject(self,
        @selector(bicSkinTapInstalled));
    if ([installed boolValue]) return;
    objc_setAssociatedObject(self, @selector(bicSkinTapInstalled),
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(bicSkin_doubleTap:)];
    tap.numberOfTapsRequired = 2;
    [self addGestureRecognizer:tap];
    bic_log(@"IMGVIEW gesture installed on %p (class=%@ img=%zux%zu)",
            self, NSStringFromClass([self class]), w, h);
}

- (void)bicSkin_doubleTap:(UITapGestureRecognizer *)gr {
    (void)gr;
    if (!g_default_image || !g_bicame_image) {
        bic_log(@"DOUBLE-TAP ignored (default=%d bicame=%d not ready)",
                g_default_image != nil, g_bicame_image != nil);
        return;
    }
    g_show_bicame = !g_show_bicame;
    [[NSUserDefaults standardUserDefaults] setBool:g_show_bicame
                                            forKey:kBicSkinShowBicameKey];
    UIImage *next = g_show_bicame ? g_bicame_image : g_default_image;
    bic_log(@"DOUBLE-TAP toggle -> showBicame=%d img=%@ (persisted)",
            g_show_bicame, next);

    UIImageView *iv = self;

    // Flip target: まず iv.superview を候補に。ただしその配下に cornerRadius
    // 付きの subview が実在すればそちらが本物の rounded カード。iv を含む
    // 枝を深さ優先で辿り、最深の "rounded かつ iv を含む" view を採用する。
    UIView *flipTarget = iv.superview ?: iv;
    UIView *rounded = bic_deepest_rounded_containing(flipTarget, iv);
    if (rounded) flipTarget = rounded;

    bic_log(@"  flip target=%@ (%p) frame=%@ radius=%.1f masksToBounds=%d",
            NSStringFromClass([flipTarget class]), flipTarget,
            NSStringFromCGRect(flipTarget.frame),
            flipTarget.layer.cornerRadius,
            flipTarget.layer.masksToBounds);
    flipTarget.layer.masksToBounds = YES;
    flipTarget.layer.allowsEdgeAntialiasing = YES;

    // 手書き Y 軸 flip。UIViewAnimationOptionTransitionFlip* は snapshot 経由で
    // rounded mask が剥がれる問題があるので、実 layer を直接回して mask を維持。
    //   default 表示側: 右回転 (FromRight)、元画像側: 左回転 (FromLeft)
    CGFloat dir = g_show_bicame ? -1.0 : 1.0;
    CATransform3D perspective = CATransform3DIdentity;
    perspective.m34 = -1.0 / 500.0;
    CATransform3D edgeOn1 = CATransform3DRotate(perspective, dir * M_PI_2, 0, 1, 0);
    CATransform3D edgeOn2 = CATransform3DRotate(perspective, -dir * M_PI_2, 0, 1, 0);
    NSTimeInterval half = 0.25;

    CABasicAnimation *a1 = [CABasicAnimation animationWithKeyPath:@"transform"];
    a1.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    a1.toValue = [NSValue valueWithCATransform3D:edgeOn1];
    a1.duration = half;
    a1.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    a1.fillMode = kCAFillModeForwards;
    a1.removedOnCompletion = NO;

    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        // edge-on の瞬間に画像を差し替え + a1 → a2 の handoff。
        // すべて implicit animation なしで一気にやってちらつきを消す。
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        [iv setImage:next];

        [flipTarget.layer removeAnimationForKey:@"bicSkinFlip1"];

        // 後半: 反対側 edge-on → 正面 (mirror 回避)
        CABasicAnimation *a2 = [CABasicAnimation animationWithKeyPath:@"transform"];
        a2.fromValue = [NSValue valueWithCATransform3D:edgeOn2];
        a2.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
        a2.duration = half;
        a2.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [flipTarget.layer addAnimation:a2 forKey:@"bicSkinFlip2"];

        [CATransaction commit];
    }];
    [flipTarget.layer addAnimation:a1 forKey:@"bicSkinFlip1"];
    [CATransaction commit];
}

@end

// ---------------------------------------------------------------------------
// DEBUG: NSJSONSerialization JSONObjectWithData: を swizzle して dummy 注入
// ---------------------------------------------------------------------------
#ifdef DEBUG
@interface NSJSONSerialization (BicSkin)
+ (id)bicSkin_JSONObjectWithData:(NSData *)data
                         options:(NSJSONReadingOptions)opt
                           error:(NSError **)err;
+ (id)bicSkin_JSONObjectWithStream:(NSInputStream *)stream
                           options:(NSJSONReadingOptions)opt
                             error:(NSError **)err;
@end

@implementation NSJSONSerialization (BicSkin)
+ (id)bicSkin_JSONObjectWithData:(NSData *)data
                         options:(NSJSONReadingOptions)opt
                           error:(NSError **)err {
    id obj = [self bicSkin_JSONObjectWithData:data options:opt error:err];
    return bic_skin_apply(obj);
}
+ (id)bicSkin_JSONObjectWithStream:(NSInputStream *)stream
                           options:(NSJSONReadingOptions)opt
                             error:(NSError **)err {
    id obj = [self bicSkin_JSONObjectWithStream:stream options:opt error:err];
    return bic_skin_apply(obj);
}
@end
#endif

// ---------------------------------------------------------------------------
// Bicame Musume 画像 prefetch — CDN からバックグラウンドで一度だけ取得してメモリに
// 載せる。失敗しても致命ではない (double-tap 側で nil-check して no-op になる)。
// ---------------------------------------------------------------------------
static void bic_prefetch_bicame_image(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSURL *url = [NSURL URLWithString:kBicSkinBicameMusumeURL];
        NSData *data = [NSData dataWithContentsOfURL:url];
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            g_bicame_image = img;
            bic_log(@"bicame image prefetch %@ (%lu bytes)",
                    img ? @"OK" : @"FAILED",
                    (unsigned long)data.length);
        });
    });
}

// ---------------------------------------------------------------------------
// Swizzler setup + ctor
// ---------------------------------------------------------------------------
static void bic_swizzle_instance(Class cls, SEL orig, SEL swiz) {
    Method mOrig = class_getInstanceMethod(cls, orig);
    Method mSwiz = class_getInstanceMethod(cls, swiz);
    if (!mOrig || !mSwiz) return;
    method_exchangeImplementations(mOrig, mSwiz);
}

static void bic_swizzle_class(Class cls, SEL orig, SEL swiz) {
    Method mOrig = class_getClassMethod(cls, orig);
    Method mSwiz = class_getClassMethod(cls, swiz);
    if (!mOrig || !mSwiz) return;
    method_exchangeImplementations(mOrig, mSwiz);
}

__attribute__((constructor))
static void bic_init(void) {
    // Substrate 版 (/var/jb) と jailed IPA 埋込版 (BicCamera.app/Frameworks) が
    // 同一プロセスに同居すると ctor が 2 回走る。method_exchangeImplementations
    // は再呼び出しで元に戻るため、素朴に swap すると swizzle が相殺される。
    //
    // dispatch_once は dylib ごとの static なのでこのケースを止められない。
    // SEL は process-wide に intern されるので、それをキーにした associated
    // object を UIImageView クラスに立ててプロセス横断のガードにする。
    SEL marker = NSSelectorFromString(@"__BicSkin_hook_installed_v1__");
    if (objc_getAssociatedObject([UIImageView class], marker)) {
        bic_log(@"===== BicSkin re-load skipped @ pid=%d (already installed) =====",
                getpid());
        return;
    }
    objc_setAssociatedObject([UIImageView class], marker,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    bic_swizzle_instance([UIImageView class],
                         @selector(setImage:),
                         @selector(bicSkin_setImage:));
    bic_prefetch_bicame_image();

    // 前回セッションで最後にトグルした側を復元
    g_show_bicame = [[NSUserDefaults standardUserDefaults]
                        boolForKey:kBicSkinShowBicameKey];

#ifdef DEBUG
    bic_swizzle_class([NSJSONSerialization class],
                      @selector(JSONObjectWithData:options:error:),
                      @selector(bicSkin_JSONObjectWithData:options:error:));
    bic_swizzle_class([NSJSONSerialization class],
                      @selector(JSONObjectWithStream:options:error:),
                      @selector(bicSkin_JSONObjectWithStream:options:error:));
    bic_log(@"===== BicSkin loaded @ pid=%d (DEBUG: dummy tampering ON) showBicame=%d =====",
            getpid(), g_show_bicame);
#else
    bic_log(@"===== BicSkin loaded @ pid=%d (RELEASE) showBicame=%d =====",
            getpid(), g_show_bicame);
#endif
}
