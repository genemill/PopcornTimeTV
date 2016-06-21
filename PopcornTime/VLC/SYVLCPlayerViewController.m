
#import "SYVLCPlayerViewController.h"
//#import "SYAppDelegate.h"
//#import "SQMovieViewController.h"
//#import "SQShowViewController.h"
//#import "SQMovieDetailViewController.h"
//#import "SQShowDetailViewController.h"
//#import "SQClientController.h"
//#import "SYContentController.h"
//#import "SYLoadingProgressView.h"
#import "SQTabMenuCollectionViewCell.h"
#import <TVVLCKit/TVVLCKit.h>
#import "SQSubSetting.h"
#import <PopcornTorrent/PopcornTorrent.h>
#import "PopcornTime-Swift.h"
#import "SRTParser.h"
#import "UIImageView+Network.h"

static NSString *const kIndex = @"kIndex";
static NSString *const kStart = @"kStart";
static NSString *const kEnd = @"kEnd";
static NSString *const kText = @"kText";

@interface SYVLCPlayerViewController () <VLCMediaPlayerDelegate, UICollectionViewDataSource, UICollectionViewDelegate, SQTabMenuCollectionViewCellDelegate, UIGestureRecognizerDelegate> {
    
    VLCMediaPlayer *_mediaplayer;
    NSURL *_url;
    NSString *_hash;
    NSArray *_cahcedSubtitles;
    
    BOOL _didParsed;
    NSMutableArray *_audioTracks;
    NSMutableArray *_subsTracks;
    BOOL _videoDidOpened;
    
    NSUInteger _tryAccount;
    NSArray *_subsTrackIndexes;
    NSDictionary *_currentSubParsed;
    NSArray *_currentSelectedSub;
    
    NSTimer *_subtitleTimer;
    float _sizeFloat;
    float _offsetFloat;
    
    BOOL _isPanning;
    CGPoint _lastPointPan;
    CGFloat _lastPointDelayPanX;
    NSIndexPath *_lastIndexPathSubtitle;
    NSIndexPath *_lastIndexPathAudio;
    
    UIPanGestureRecognizer *_panGestureRecognizer;
    UIPanGestureRecognizer *_panGestureRecognizerDelay;
    
    CGPoint _panGestureDeltaPoint; // Calcula la cantidad de variacion que ha habido en ambas coordenadas (diferencia de signo en cada detección)
    BOOL _finishAnalyzePan;
    BOOL _didPanGesture;
    BOOL _didClickGesture;
    BOOL _panChangingTime;
    NSUInteger _lastButtonSelectedTag;

    SQSubSetting *subSetting;
    
    NSDictionary *_videoInfo;
    NSString *_magnet;
    
    BOOL _videoLoaded;
}

@end


@implementation SYVLCPlayerViewController

#define kAlphaFocused 1.0
#define kAlphaNotFocused 0.25
#define kAlphaFocusedBackground 0.5
#define kAlphaNotFocusedBackground 0.15

- (id)initWithVideoInfo:(NSDictionary *)videoInfo {
    self = [super init];
    
    if (self) {
        _lastButtonSelectedTag = 1;
        _finishAnalyzePan = NO;
        _didPanGesture = NO;
        _didClickGesture = NO;
        _videoDidOpened = NO;
        self.currentSubTitleDelay = .0;
        _tryAccount = 0;
        _isPanning  = NO;
        _sizeFloat = 68.0;
        _panChangingTime = NO;
        
        // Settings object
        subSetting = [SQSubSetting loadFromDisk];
        
        _videoInfo = videoInfo;
        _magnet = _videoInfo[@"magnet"];
        _videoLoaded = NO;
        
        [self beginStreamingTorrent];
    }
    
    return self;
}

- (id) initWithURL:(NSURL *) url imdbID:(NSString *) hash subtitles:(NSArray *)cahcedSubtitles
{
    self = [super init];
    
    if (self) {
        _lastButtonSelectedTag = 1;
        _finishAnalyzePan = NO;
        _didPanGesture = NO;
        _didClickGesture = NO;
        _url = url;
        _videoDidOpened = NO;
        _hash = hash;
        _cahcedSubtitles = cahcedSubtitles;
        self.currentSubTitleDelay = .0;
        _tryAccount = 0;
        _isPanning  = NO;
        _sizeFloat = 68.0;
        _panChangingTime = NO;
        
        // Settings object
        subSetting = [SQSubSetting loadFromDisk];
    }
    
    return self;
    
}// initWithURL:


- (void)beginStreamingTorrent {
    // lets not get a retain cycle going
    __weak __typeof__(self) weakSelf = self;
    [[PTTorrentStreamer sharedStreamer] startStreamingFromFileOrMagnetLink:_magnet progress:^(PTTorrentStatus status) {
        
        // Percentage
        _percentLabel.text = [NSString stringWithFormat:@"%.0f%%", status.bufferingProgress * 100];
        
        // Status
        NSString *speedString = [NSByteCountFormatter stringFromByteCount:status.downloadSpeed countStyle:NSByteCountFormatterCountStyleBinary];
        _statsLabel.text = [NSString stringWithFormat:@"Overall Progress: %.0f%%  Speed: %@/s  Seeds: %d  Peers: %d", status.totalProgreess * 100, speedString, status.seeds, status.peers];
//        NSLog(@"%.0f%%, %.0f%%, %@/s, %d,- %d", status.bufferingProgress*100, status.totalProgreess*100, speedString, status.seeds, status.peers);
        
        // State
        _overallProgressView.progress = status.totalProgreess;
        _progressView.progress = status.bufferingProgress;
        if (_progressView.progress > 0.0) {
            [_nameLabel.text stringByReplacingOccurrencesOfString:@"Processing" withString:@"Buffering"];
        }
    } readyToPlay:^(NSURL *videoFileURL) {
        _url = videoFileURL;
        _videoLoaded = YES;
        [weakSelf createAudioSubsDatasource];
        [weakSelf updateLoadingRatio];
        [weakSelf loadPlayer];
    } failure:^(NSError *error) {
        // Throw up an error and dismiss the view
        [weakSelf showAlertLoadingView];
    }];
}

- (void)stopStreamingTorrent {
    [[PTTorrentStreamer sharedStreamer] cancelStreaming];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.view canBecomeFocused];
    
    // Sub back
    if (subSetting.backgroundType == SQSubSettingBackgroundBlack) {
        self.backSubtitleView.backgroundColor = [UIColor colorWithWhite:.0 alpha:0.9];
    }
    else if (subSetting.backgroundType == SQSubSettingBackgroundWhite) {
        self.backSubtitleView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    }
    
    // Subs
    {
        UICollectionViewFlowLayout *collectionViewFlowLayout = [[UICollectionViewFlowLayout alloc]init];
        collectionViewFlowLayout.itemSize = CGSizeMake(228, 390);
        collectionViewFlowLayout.sectionInset = UIEdgeInsetsMake(0, 90.0, 0, 90.0);
        collectionViewFlowLayout.minimumInteritemSpacing = 0;
        collectionViewFlowLayout.minimumLineSpacing = 0;
        collectionViewFlowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        
        UINib *cellNib = [UINib nibWithNibName:@"SQTabMenuCollectionViewCell" bundle:nil];
        [self.subTabBarCollectionView registerNib:cellNib forCellWithReuseIdentifier:@"TabMenuCollectionViewCell"];
        [self.subTabBarCollectionView setCollectionViewLayout:collectionViewFlowLayout];
        [self.subTabBarCollectionView setContentInset:UIEdgeInsetsMake(.0, .0, .0, .0)];
        self.subTabBarCollectionView.remembersLastFocusedIndexPath = YES;
    }
    
    // Audio
    {
        UICollectionViewFlowLayout *collectionViewFlowLayout = [[UICollectionViewFlowLayout alloc]init];
        collectionViewFlowLayout.itemSize = CGSizeMake(228, 390);
        collectionViewFlowLayout.sectionInset = UIEdgeInsetsMake(0, 90.0, 0, 90.0);
        collectionViewFlowLayout.minimumInteritemSpacing = 0;
        collectionViewFlowLayout.minimumLineSpacing = 0;
        collectionViewFlowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        
        UINib *cellNib = [UINib nibWithNibName:@"SQTabMenuCollectionViewCell" bundle:nil];
        [self.audioTabBarCollectionView registerNib:cellNib forCellWithReuseIdentifier:@"TabMenuCollectionViewCell"];
        [self.audioTabBarCollectionView setCollectionViewLayout:collectionViewFlowLayout];
        [self.audioTabBarCollectionView setContentInset:UIEdgeInsetsMake(.0, .0, .0, .0)];
        self.audioTabBarCollectionView.remembersLastFocusedIndexPath = YES;
    }
    
    _mediaplayer              = [[VLCMediaPlayer alloc] init];
    _mediaplayer.drawable     = self.containerView;
    _mediaplayer.delegate     = self;
    _mediaplayer.audio.volume = 200;
    
    self.lineBackView.layer.cornerRadius  = 6.0;
    self.lineBackView.layer.masksToBounds = YES;
    
    self.backSubtitleView.layer.cornerRadius  = 10.0;
    self.backSubtitleView.layer.masksToBounds = YES;
    
    // Exit filters
    UITapGestureRecognizer *menuButtonResetFiltersSearch = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(menuButton:)];
    menuButtonResetFiltersSearch.allowedPressTypes = @[[NSNumber numberWithInteger:UIPressTypeMenu]];
    [self.view addGestureRecognizer:menuButtonResetFiltersSearch];
    
    // Play/Pause
    UITapGestureRecognizer *playPauseTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playandPause:)];
    playPauseTapGesture.allowedPressTypes = @[@(UIPressTypePlayPause)];
    [self.view addGestureRecognizer:playPauseTapGesture];
    
    // Pan
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGesture:)];
    _panGestureRecognizer.delegate = self;
    [self.view addGestureRecognizer:_panGestureRecognizer];
    
    // Pan Delay
    _panGestureRecognizerDelay = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureDelay:)];
    _panGestureRecognizerDelay.delegate = self;
    [self.subValueDelayButton addGestureRecognizer:_panGestureRecognizerDelay];

    if (_videoInfo) {
        _statsLabel.text = @"";
        _percentLabel.text = @"0%";
        _nameLabel.text = [NSString stringWithFormat:@"Processing %@...", _videoInfo[@"movieName"]];
        
        [_imageView loadImageFromURL:[NSURL URLWithString:_videoInfo[@"imageAddress"]] placeholderImage:nil];
        [_backgroundImageView loadImageFromURL:[NSURL URLWithString:_videoInfo[@"backgroundImageAddress"]] placeholderImage:nil];
    }
    
    if (_url) {
        [self loadPlayer];
    }
}

- (void)loadPlayer {
    [_loadingView setHidden:YES];
    
    [self showOSD];
    [self hideDelayButton];
    
    self.heightCurrentLineSpace.constant = 25.0;
    [self.view layoutIfNeeded];
    
    // Media player
    _mediaplayer.media = [VLCMedia mediaWithURL:_url];
    [_mediaplayer play];
    
    self.subsButton.enabled      = NO;
    self.subsDelayButton.enabled = NO;
    self.audioButton.enabled     = NO;
}


- (void) dealloc
{
    NSLog(@"dealloc SYVLCPlayerController");
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateLoadingRatio) object:nil];
}


- (void) updateLoadingRatio
{

}


- (void) showAlertLoadingView
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"Error")
                                                                   message:NSLocalizedString(@"Could not load this video", @"Could not load this video")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* acceptAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Accept", @"Accept")
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * action) {
                                                             [_mediaplayer stop];
                                                             _mediaplayer.delegate = nil;
                                                             _mediaplayer = nil;
                                                             
                                                             [self stopStreamingTorrent];
                                                             [self.navigationController popViewControllerAnimated:YES];
                                                         }];
    [alert addAction:acceptAction];
    [self presentViewController:alert animated:YES completion:nil];
    
}


- (IBAction)menuButton:(id)sender
{
    if ([self isTopMenuOnScreen]) {
        NSLog(@"Menu Out");
        [self closeTopMenu];
    }
    else {
        [self done:sender];
    }
}


#pragma mark - Gesture Low level

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    //NSLog(@"touchesEnded: %@ - %@", touches, event);
    
    if (self.osdView.alpha == .0) {
        _isPanning = YES;
        
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideOSD) object:nil];
        [self performSelector:@selector(hideOSD) withObject:nil afterDelay:5.0];
        [self showOSD];
        [self showSwipeMessage];
        
        if (_didClickGesture) {
            _didClickGesture = NO;
        }
    } else if (self.topTopMenuSpace.constant != .0) {
        
        if (!_didClickGesture && !_didPanGesture) {
            _isPanning = NO;
            [self hideOSD];
        }
        
        if (_didPanGesture) {
            _didPanGesture = NO;
        }
        
        if (_didClickGesture) {
            _didClickGesture = NO;
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    //NSLog(@"touchesMoved : %i", [self isOSDOnScreen]);
    _isPanning = YES;
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
    //NSLog(@"pressesEnded: %@ - %@", presses, event);
    
    if ([presses count] == 0) {
        return;
    }
    
    UIPress *press = [presses anyObject];
    
    _didClickGesture = YES;
    
    // Click on everywhere
    if (press.type == 4) {
        if ([self isTopMenuOnScreen]) {
            if (!self.audioButton.focused &&
                !self.subsButton.focused &&
                !self.subsDelayButton.focused) {
                [self closeTopMenu];
                NSLog(@"A Click anywhere");
            }
        }
        else {
            [self playandPause:nil];
        }
    }/*
    // Touch Left
    else if (press.type == 2) {
        
    }
    // Touch Right
    else if (press.type == 3) {
        
    }
    // Touch Up
    else if (press.type == 0) {
        
    }
    // Touch Down
    else if (press.type == 1) {
        
    }*/

}


#pragma mark - Change focus

- (UIView *) preferredFocusedView
{
    if (![self isTopMenuOnScreen]) {
        return self.view;
    }
    
    if ([self.subValueDelayButton isFocused]) {
        
        self.subsButton.enabled      = YES;
        self.subsDelayButton.enabled = YES;
        self.audioButton.enabled     = YES;
        
        return self.subsDelayButton;
    }
    
    if ([self.topButton isFocused]) {
        
        self.subsButton.enabled     = YES;
        self.subsDelayButton.enabled = YES;
        self.audioButton.enabled    = YES;
        
        switch (_lastButtonSelectedTag) {
            case 1:
                return self.subsButton;
                break;
            case 2:
                return self.subsDelayButton;
                break;
            default:
                return self.audioButton;
                break;
        }
    }
    
    return self.view;
    
}// preferredFocusedView


- (void) didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator
{
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    
    //NSLog(@"didUpdateFocusInContext : %@", context.nextFocusedView);
    
    if ([context.nextFocusedView isKindOfClass:[UIButton class]]) {
        //NSLog(@"next: button (%li)", context.nextFocusedView.tag);
    }
    if ([context.nextFocusedView isKindOfClass:[SQTabMenuCollectionViewCell class]]) {
        //NSLog(@"next: cell");
    }
    if ([context.previouslyFocusedView isKindOfClass:[UIButton class]]) {
        //NSLog(@"previous: button (%li)", context.previouslyFocusedView.tag);
    }
    if ([context.previouslyFocusedView isKindOfClass:[SQTabMenuCollectionViewCell class]]) {
        //NSLog(@"previous: cell");
    }
    
    if ([context.previouslyFocusedView isKindOfClass:[SQTabMenuCollectionViewCell class]]) {
        self.subsButton.enabled      = NO;
        self.subsDelayButton.enabled = NO;
        self.audioButton.enabled     = NO;
        
        if (![context.nextFocusedView isKindOfClass:[SQTabMenuCollectionViewCell class]]) {
            SQTabMenuCollectionViewCell *tabCell = (SQTabMenuCollectionViewCell *) context.previouslyFocusedView;
            tabCell.nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:kAlphaNotFocused];
        }
    }
    
    if ([context.nextFocusedView isKindOfClass:[SQTabMenuCollectionViewCell class]]) {
        [self activeCollectionViews];
        [self deactiveHeaderButtons];
    }
    
    BOOL nextFocusedIsHeaderButton = (context.nextFocusedView.tag > 0 && context.nextFocusedView.tag < 4);
    BOOL previousFocusedIsHeaderButton = (context.previouslyFocusedView.tag > 0 && context.previouslyFocusedView.tag < 4);
    
    if (nextFocusedIsHeaderButton) {
        _lastButtonSelectedTag = context.nextFocusedView.tag;
        
        self.subTabBarCollectionView.hidden   = (_lastButtonSelectedTag != 1);
        self.subValueDelayButton.hidden       = (_lastButtonSelectedTag != 2);
        self.audioTabBarCollectionView.hidden = (_lastButtonSelectedTag != 3);
        
        if (!previousFocusedIsHeaderButton) {
            [self deactiveCollectionViews];
            [self activeHeaderButtons];
        }
        else {
            [self deactiveHeaderButtons];
        }
    } else if (context.nextFocusedView.tag == 1001) {
        if ([context.previouslyFocusedView isKindOfClass:[SQTabMenuCollectionViewCell class]]) {
            [self deactiveCollectionViews];
//            self.middleButton.hidden = YES;
            [self setNeedsFocusUpdate];
        } else {
            [self closeTopMenu];
//            NSLog(@"Update Focus");
        }
    }
    
    if (context.nextFocusedView.tag == 4) {
        [self deactiveHeaderButtons];
        [self.subValueDelayButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:kAlphaFocused] forState:UIControlStateFocused];
    } else if (context.previouslyFocusedView.tag == 4) {
//        self.middleButton.hidden = YES;
        [self activeHeaderButtons];
        [self.subValueDelayButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:kAlphaFocusedBackground] forState:UIControlStateFocused];
    }

}


- (BOOL)shouldUpdateFocusInContext:(UIFocusUpdateContext *)context
{
    return YES;
}


#pragma mark - Top Menu

- (void) openTopMenu
{
    [self hideSwipeMessage];

    self.subsButton.enabled      = NO;
    self.subsDelayButton.enabled = NO;
    self.audioButton.enabled     = NO;

    self.topTopMenuSpace.constant = .0;

    _panGestureRecognizer.enabled = NO;
    
    _topMenuContainerView.hidden = NO;
    _topButton.hidden            = NO;
    
    [UIView animateWithDuration:0.3 animations:^{
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        [self setNeedsFocusUpdate];
    }];
}


- (void) closeTopMenu
{
    _finishAnalyzePan = NO;
    _didPanGesture = NO;
    _didClickGesture = NO;
    _isPanning  = NO;
    _panChangingTime = NO;
    
    self.topTopMenuSpace.constant = -232.0;

    _panGestureRecognizer.enabled = YES;
    
    [UIView animateWithDuration:0.3 animations:^{
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        _topMenuContainerView.hidden = YES;
        _topButton.hidden            = YES;
        [self setNeedsFocusUpdate];
        [self performSelector:@selector(hideOSD) withObject:nil afterDelay:4.0];
        [self showSwipeMessage];
    }];
}


- (BOOL) isTopMenuOnScreen
{
    return (!_topMenuContainerView.hidden);
}


- (void) showMiddleButton
{
//    self.middleButton.hidden = NO;
    
}


- (void) hideMiddleButton
{
//    self.middleButton.hidden = YES;
    
}


#pragma mark - Actions

- (IBAction)playandPause:(id)sender
{
    [self showOSD];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideOSD) object:nil];
    [self performSelector:@selector(hideOSD) withObject:nil afterDelay:4.0];
    
    if (_mediaplayer.isPlaying) {
        [_mediaplayer pause];
        return;
    }
    
    [_mediaplayer play];
    
}


- (IBAction)panGesture:(id)sender
{
    
//    NSLog(@"panGesture");
    
    if (!_videoLoaded) return;

    UIPanGestureRecognizer *panGestureRecognizer = (UIPanGestureRecognizer *) sender;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideOSD) object:nil];
    
    if (panGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        _panGestureDeltaPoint = CGPointZero;
        _finishAnalyzePan = NO;
        
        if (self.osdView.alpha == 0) {
            [self showOSD];
            [self showSwipeMessage];
        } else {
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(playDelay) object:nil];
            
            _isPanning = YES;
            self.heightCurrentLineSpace.constant = 40.0;
            [UIView animateWithDuration:0.3 animations:^{
                [self.view layoutIfNeeded];
            }];
        }
    } else if (panGestureRecognizer.state == UIGestureRecognizerStateChanged) {
        CGPoint currentPoint = [panGestureRecognizer translationInView:self.view];
        
        if (!_finishAnalyzePan) {
            CGFloat deltaX = fabs(currentPoint.x) - fabs(_lastPointPan.x);
            CGFloat deltaY = _lastPointPan.y - currentPoint.y;
            CGFloat yValue = (deltaY < .0) ? .0 : _panGestureDeltaPoint.y + deltaY;
            
            _panGestureDeltaPoint = CGPointMake(_panGestureDeltaPoint.x + fabs(deltaX), yValue);
            
            if (deltaY < -50.0) {
                _panGestureRecognizer.cancelsTouchesInView = YES;
                _finishAnalyzePan = YES;
                [self openTopMenu];
            } else if (deltaX > 100.0) {
                if (![_mediaplayer isPlaying]) {
                    [self showOSD];
                    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(playDelay) object:nil];
                    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideOSD) object:nil];
                    
                    _finishAnalyzePan = YES;
                    [_mediaplayer pause];
                    _panChangingTime = YES;
                }
            }
        }
        
        if (_isPanning && _finishAnalyzePan) {
            
            _didPanGesture = YES;
            _leftCurrentLineSpace.constant += ((currentPoint.x - _lastPointPan.x) * 0.15);
            
            if (_leftCurrentLineSpace.constant < 100.0) {
                _leftCurrentLineSpace.constant = 100.0;
            }
            else if (_leftCurrentLineSpace.constant > self.lineBackView.frame.size.width+100) {
                _leftCurrentLineSpace.constant = self.lineBackView.frame.size.width+100;
            }
            
            [self.view layoutIfNeeded];
            _lastPointPan = currentPoint;
            
            float position = (_leftCurrentLineSpace.constant - 100.0) / self.lineBackView.frame.size.width;
            NSLog(@"%f - %f", position, self.overallProgressView.progress);
            if (position >= self.overallProgressView.progress) {
                NSLog(@"CANT LOAD PAST THE DOWNLOADED POINT");
            } else {
                NSLog(@"Safe to load");
            }
            
            // Left label
            {
                int actualSeconds = (int) (([[_mediaplayer time]intValue] - [[_mediaplayer remainingTime]intValue]) * 0.001 * position);
                div_t hours = div(actualSeconds,3600);
                div_t minutes = div(hours.rem,60);
                int seconds = minutes.rem;
                
                self.leftLabel.text = [NSString stringWithFormat:@"%02d:%02d:%02d", hours.quot, minutes.quot, seconds];
            }
            
            // Right Label
            {
                int remainingSeconds = (int) (([[_mediaplayer time]intValue] - [[_mediaplayer remainingTime]intValue]) * 0.001 * (1.0 - position));
                div_t hours = div(remainingSeconds,3600);
                div_t minutes = div(hours.rem,60);
                int seconds = minutes.rem;
                
                self.rightLabel.text = [NSString stringWithFormat:@"%02d:%02d:%02d", hours.quot, minutes.quot, seconds];
            }
        }
    } else if (panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
        _finishAnalyzePan = NO;
        float position = (_leftCurrentLineSpace.constant - 100.0) / self.lineBackView.frame.size.width;
        [_mediaplayer pause];
        [_mediaplayer setPosition:position];

        self.indicatorView.hidden = NO;
        
        if (position == 1.0) {
            [self done:panGestureRecognizer];
        } else {
            [self performSelector:@selector(playDelay) withObject:nil afterDelay:2.0];
            [self performSelector:@selector(hideOSD) withObject:nil afterDelay:5.0];
        }
    }
    
//    _isPanning = NO;
//    _panChangingTime = NO;
//    _panGestureRecognizer.cancelsTouchesInView = NO;
//    
//    self.heightCurrentLineSpace.constant = 25.0;
//    [UIView animateWithDuration:0.3 animations:^{
//        [self.view layoutIfNeeded];
//    }];
//    
//    _lastPointPan = CGPointZero;
}


- (IBAction)panGestureDelay:(id)sender
{
    //NSLog(@"panGestureDelay");
    
    if (_panGestureRecognizerDelay.state == UIGestureRecognizerStateBegan) {
        
        _panGestureDeltaPoint = CGPointZero;
        _finishAnalyzePan = NO;
        
        if (self.osdView.alpha == 0) {
            [self showOSD];
            [self showSwipeMessage];
        }
    } else if (_panGestureRecognizerDelay.state == UIGestureRecognizerStateChanged) {
        
        CGPoint currentPoint = [_panGestureRecognizerDelay translationInView:self.view];
        
        if (!_finishAnalyzePan) {
            CGFloat deltaX = fabs(currentPoint.x) - fabs(_lastPointPan.x);
            CGFloat deltaY = _lastPointPan.y - currentPoint.y;
            CGFloat yValue = (deltaY < .0) ? .0 : _panGestureDeltaPoint.y + deltaY;
            
            _panGestureDeltaPoint = CGPointMake(_panGestureDeltaPoint.x + fabs(deltaX), yValue);
            
            if (deltaY > 50.0) {
                _panGestureRecognizer.cancelsTouchesInView = YES;
                _finishAnalyzePan = YES;
                [self setNeedsFocusUpdate];
            } else if (deltaX > 100.0) {
                _finishAnalyzePan = YES;
            }
        }
        
        
        if (_finishAnalyzePan) {
            _offsetFloat += ((currentPoint.x - _lastPointDelayPanX) * 0.005);
            NSString *signStr = (_offsetFloat > 0) ? @"+" : @"";
            NSString *delayValue = [NSString stringWithFormat:@"%@%4.2f", signStr, (roundf(_offsetFloat) * 5.0) / 10.0];
            [self.subValueDelayButton setTitle:delayValue forState:UIControlStateNormal];
        }
        
        _lastPointDelayPanX = currentPoint.x;
    }
    
    _panGestureRecognizerDelay.cancelsTouchesInView = NO;
    _lastPointPan = CGPointZero;
}


- (void) playDelay
{
    [_mediaplayer play];
    self.indicatorView.hidden = YES;
    
}


- (IBAction)done:(id)sender
{
    if (!self.topMenuContainerView.hidden) {
        [self closeTopMenu];
        return;
    }
    
    if ([sender isKindOfClass:[UITapGestureRecognizer class]]) {
        UITapGestureRecognizer *tapGestureRecognizer = (UITapGestureRecognizer *) sender;
        
        if (tapGestureRecognizer.state == UIGestureRecognizerStateEnded) {
            
            // Si hay entrado realmente en el video
            // guarda el ratio
            if (_videoDidOpened) {
//            if (_videoDidOpened && _hash.length > 0) {
                
//                float ratio = [self currentTimeAsPercentage];
//                if (ratio > 0.95) {
//                    ratio = 1.0;
//                }
                
                NSArray *viewControllers = [self.navigationController viewControllers];
                
                for (NSInteger i = [viewControllers count]-1 ; i >= 0 ; i--) {
                    
//                    id object = viewControllers[i];
                    
                    /*
                    if ([object isKindOfClass:[SQMovieDetailViewController class]]) {
                        SQMovieDetailViewController *detailViewController = (SQMovieDetailViewController *) object;
                        [[SYContentController shareController]setRatio:ratio toMovie:detailViewController.imdb];
                        break;
                    }
                    else if ([object isKindOfClass:[SQShowDetailViewController class]]) {
                        SQShowDetailViewController *detailViewController = (SQShowDetailViewController *) object;
                        [[SYContentController shareController]setRatio:ratio
                                                             toEpisode:detailViewController.episodeSelected
                                                             withBlock:^(NSData *data, NSError *error) {
                                                                 [detailViewController setRatio:ratio];
                                                             }];
                        break;
                    }
                     */
                }
                
                [self rememberAudioSub];
                
            }
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateLoadingRatio) object:nil];
            
            [_mediaplayer stop];
            _mediaplayer.delegate = nil;
            _mediaplayer = nil;
            
//            [[SQClientController shareClient]stopStreamingWithHash:_hash withBlock:nil];
            
            [self stopStreamingTorrent];
            
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
    else if (!sender || [sender isKindOfClass:[UIPanGestureRecognizer class]]) {
        UIPanGestureRecognizer *panGestureRecognizer = (UIPanGestureRecognizer *) sender;
        
        if (!sender || panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
            /*
            if (_hash.length > 0) {
                float ratio = 1.0;
                
                NSArray *viewControllers = [[self.rootViewController navigationController]viewControllers];
                
                for (NSInteger i = [viewControllers count]-1 ; i >= 0 ; i--) {
                    
                    id object = viewControllers[i];
                    
                    if ([object isKindOfClass:[SQMovieDetailViewController class]]) {
                        SQMovieDetailViewController *detailViewController = (SQMovieDetailViewController *) object;
                        [[SYContentController shareController]setRatio:ratio toMovie:detailViewController.imdb];
                        break;
                    }
                    else if ([object isKindOfClass:[SQShowDetailViewController class]]) {
                        SQShowDetailViewController *detailViewController = (SQShowDetailViewController *) object;
                        [[SYContentController shareController]setRatio:ratio toEpisode:detailViewController.episodeSelected withBlock:^(NSData *data, NSError *error) {
                            [self.rootViewController setRatio:ratio];
                        }];
                        
                        break;
                    }
                }
                
                [self rememberAudioSub];
            }
             */
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateLoadingRatio) object:nil];
            
            [_mediaplayer stop];
            _mediaplayer.delegate = nil;
            _mediaplayer = nil;
            
//            [[SQClientController shareClient]stopStreamingWithHash:_hash withBlock:nil];
            
            [self stopStreamingTorrent];
            
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
    
}


- (void) rememberAudioSub
{
    Subtitle *subSelected = _subsTracks[_lastIndexPathSubtitle.row];
    //NSDictionary *audioSelected = _audioTracks[_lastIndexPathAudio.row];
    //NSLog(@"audio : %@", audioSelected);
    
    NSString *currentSubs = [[subSelected language] lowercaseString];
    if (currentSubs) {
        [[NSUserDefaults standardUserDefaults] setValue:currentSubs forKey:@"currentSubs"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}


#pragma mark - VLC Delegate

- (void) mediaPlayerStateChanged:(NSNotification *)aNotification
{
    VLCMediaPlayer *player = [aNotification object];
    //NSLog(@"mediaPlayerStateChanged");
    switch(player.state) {
        case VLCMediaPlayerStateStopped: {
            //NSLog(@"VLCMediaPlayerStateStopped");
            [self done:nil];
            break;
        }
        case VLCMediaPlayerStateOpening:
            //NSLog(@"VLCMediaPlayerStateOpening");
            break;
        case VLCMediaPlayerStateBuffering:
            self.indicatorView.hidden = NO;
            //NSLog(@"VLCMediaPlayerStateBuffering");
            break;
        case VLCMediaPlayerStateEnded:
            //NSLog(@"VLCMediaPlayerStateEnded");
            break;
        case VLCMediaPlayerStateError:
            //NSLog(@"VLCMediaPlayerStateError");
            [self done:nil];
            break;
        case VLCMediaPlayerStatePlaying:
            //NSLog(@"VLCMediaPlayerStatePlaying");
            break;
            // Error al abrir fichero con DRM
        case VLCMediaPlayerStatePaused:
            //NSLog(@"VLCMediaPlayerStatePaused");
            break;
    }
    
}// mediaPlayerStateChanged:


- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification
{
    self.indicatorView.hidden = YES;
    
    [self resumeSubtitleParseTimerIfNeeded];
    
    if (!_videoDidOpened) {
        
        self.swipeTopConstraint.constant = 30.0;
        self.osdView.alpha = .0;
        self.swipeMesaggeContainerView.alpha = .0;
        
        self.osdView.hidden = NO;
        self.swipeMesaggeContainerView.hidden = NO;
        
        [self showOSD];
        [self showSwipeMessage];
        
        if (_initialRatio != 0) {
            [_mediaplayer setPosition:_initialRatio];
        }
        [self createAudioSubsDatasource];
        [self performSelector:@selector(hideOSD) withObject:nil afterDelay:5.0];
        
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateLoadingRatio) object:nil];
        
        [UIView animateWithDuration:0.3 animations:^{
            self.loadingLogo.alpha = .0;
//            self.progressView.alpha = .0;
            self.indicatorView.alpha = 1.0;
        }];
        
        _videoDidOpened = YES;
    }
 
    self.indicatorView.hidden = YES;

    if (!_panChangingTime) {
        self.leftLabel.text   = [self currentTimeAsString];
        self.rightLabel.text  = [self durationToEndAsString];
        
        CGFloat width = self.lineBackView.frame.size.width;
        CGFloat ratio = [self currentTimeAsPercentage];
        self.leftCurrentLineSpace.constant = 100.0 + (width * ratio);
        
        if (ratio >= 1.0) {
            [self done:nil];
        }
    }
    
}


#pragma mark - OSD

- (void) showSwipeMessage
{
    
    if (self.swipeTopConstraint.constant == 26) {
        return;
    }
    
    self.swipeTopConstraint.constant = 26;
    
    [UIView animateWithDuration:0.3 animations:^{
        self.swipeMesaggeContainerView.alpha = 1.0;
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
    }];
}


- (void) hideSwipeMessage
{
    if (self.swipeTopConstraint.constant == 36) {
        return;
    }
    
    self.swipeTopConstraint.constant = 36;
    
    [UIView animateWithDuration:0.3 animations:^{
        self.swipeMesaggeContainerView.alpha = .0;
        [self.view layoutIfNeeded];
    }completion:^(BOOL finished) {
    }];
}


- (void) showOSD
{
    self.subtitlesBottomSpace.constant = 120.0;
    
    [UIView animateWithDuration:0.4 animations:^{
        self.osdView.alpha = 1.0;
        [self.view layoutIfNeeded];
    }];
}


- (void) hideOSD
{
    _isPanning = NO;
    self.subtitlesBottomSpace.constant = 72.0;
    
    [self hideSwipeMessage];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideOSD) object:nil];
    [UIView animateWithDuration:0.4 animations:^{
        self.osdView.alpha = .0;
        [self.view layoutIfNeeded];
    }completion:^(BOOL finished) {
    }];
}


- (BOOL) isOSDOnScreen
{
    return (self.osdView.alpha == 1.0);
}


#pragma mark - Active/Deactive CollectionViews

- (void) activeCollectionViews
{
    for (SQTabMenuCollectionViewCell *cell in [self.subTabBarCollectionView visibleCells]) {
        NSIndexPath *indexPath = [self.subTabBarCollectionView indexPathForCell:cell];
        float alpha = (indexPath.row == _lastIndexPathSubtitle.row) ? kAlphaFocused : kAlphaNotFocused;
        cell.nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
    }
    
    for (SQTabMenuCollectionViewCell *cell in [self.audioTabBarCollectionView visibleCells]) {
        NSIndexPath *indexPath = [self.audioTabBarCollectionView indexPathForCell:cell];
        float alpha = (indexPath.row == _lastIndexPathAudio.row) ? kAlphaFocused : kAlphaNotFocused;
        cell.nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
    }
}


- (void) deactiveCollectionViews
{
    for (SQTabMenuCollectionViewCell *cell in [self.subTabBarCollectionView visibleCells]) {
        NSIndexPath *indexPath = [self.subTabBarCollectionView indexPathForCell:cell];
        float alpha = (indexPath.row == _lastIndexPathSubtitle.row) ? kAlphaFocusedBackground : kAlphaNotFocusedBackground;
        cell.nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
    }
    
    for (SQTabMenuCollectionViewCell *cell in [self.audioTabBarCollectionView visibleCells]) {
        NSIndexPath *indexPath = [self.audioTabBarCollectionView indexPathForCell:cell];
        float alpha = (indexPath.row == _lastIndexPathAudio.row) ? kAlphaFocusedBackground : kAlphaNotFocusedBackground;
        cell.nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
    }
}


- (void) activeHeaderButtons
{
    UIColor *selectedColor = [UIColor colorWithWhite:1.0 alpha:kAlphaFocused];
    UIColor *unSelectedColor = [UIColor colorWithWhite:1.0 alpha:kAlphaNotFocused];
    
    [self.subsButton setTitleColor:(self.subTabBarCollectionView.hidden) ? unSelectedColor : selectedColor
                          forState:UIControlStateNormal];
    [self.subsDelayButton setTitleColor:(self.subValueDelayButton.hidden) ? unSelectedColor : selectedColor
                               forState:UIControlStateNormal];
    [self.audioButton setTitleColor:(self.audioTabBarCollectionView.hidden) ? unSelectedColor : selectedColor
                           forState:UIControlStateNormal];
    
}


- (void) deactiveHeaderButtons
{
    UIColor *selectedColor = [UIColor colorWithWhite:1.0 alpha:kAlphaFocusedBackground];
    UIColor *unSelectedColor = [UIColor colorWithWhite:1.0 alpha:kAlphaNotFocusedBackground];
    
    [self.subsButton setTitleColor:(self.subTabBarCollectionView.hidden) ? unSelectedColor : selectedColor
                          forState:UIControlStateNormal];
    [self.subsDelayButton setTitleColor:(self.subValueDelayButton.hidden) ? unSelectedColor : selectedColor
                               forState:UIControlStateNormal];
    [self.audioButton setTitleColor:(self.audioTabBarCollectionView.hidden) ? unSelectedColor : selectedColor
                           forState:UIControlStateNormal];
    
}


#pragma mark - UICollectionView Data Source

- (NSInteger) collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    if ([collectionView isEqual:self.subTabBarCollectionView]) {
        return [_subsTracks count];
    }
    else {
        return [_audioTracks count];
    }
    
}// collectionView:numberOfItemsInSection:


- (UICollectionViewCell *) collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"TabMenuCollectionViewCell";
    
    SQTabMenuCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
    cell.delegate = self;
    if ([collectionView isEqual:self.subTabBarCollectionView]) {
        Subtitle *item = [_subsTracks objectAtIndex:indexPath.row];
        cell.nameLabel.text = item.language;
    } else {
        NSDictionary *item = [_audioTracks objectAtIndex:indexPath.row];
        cell.nameLabel.text = item[@"name"];
    }
    
    if ([collectionView isEqual:self.subTabBarCollectionView]) {
        cell.collectionViewType = SQTabMenuCollectionViewTypeSubtitle;
        float alpha = (indexPath.row == _lastIndexPathSubtitle.row) ? kAlphaFocusedBackground : kAlphaNotFocusedBackground;
        cell.nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
    } else {
        cell.collectionViewType = SQTabMenuCollectionViewTypeAudio;
        float alpha = (indexPath.row == _lastIndexPathSubtitle.row) ? kAlphaFocusedBackground : kAlphaNotFocusedBackground;
        cell.nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
    }
    
    return cell;
    
}// collectionView:cellForItemAtIndexPath


- (void) collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([collectionView isEqual:self.subTabBarCollectionView]) {
        [self newSubSelected];
        [self closeTopMenu];
    } else if ([collectionView isEqual:self.audioTabBarCollectionView]) {
        [self newAudioSelected];
        [self closeTopMenu];
    }
    
}// collectionView:didSelectItemAtIndexPath:


#pragma mark - Select Items

- (void) newItemSelected:(id) cell
{
    [self performSelector:@selector(showMiddleButton) withObject:nil afterDelay:1.0];
    
    if ([cell isKindOfClass:[SQTabMenuCollectionViewCell class]]) {
        SQTabMenuCollectionViewCell *tabCell = (SQTabMenuCollectionViewCell *) cell;
        
        // Sub
        if (tabCell.collectionViewType == SQTabMenuCollectionViewTypeSubtitle) {
            if (_lastIndexPathSubtitle) {
                SQTabMenuCollectionViewCell *lastCell = (SQTabMenuCollectionViewCell *)[_subTabBarCollectionView cellForItemAtIndexPath:_lastIndexPathSubtitle];
                lastCell.nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:kAlphaNotFocusedBackground];
            }
            
            tabCell.nameLabel.textColor = [UIColor whiteColor];
            _lastIndexPathSubtitle = [self.subTabBarCollectionView indexPathForCell:tabCell];
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(newSubSelected) object:nil];
            [self performSelector:@selector(newSubSelected) withObject:nil afterDelay:2.0];
            
            if (_lastIndexPathSubtitle.row != 0) {
                [self showDelayButton];
            }
            else {
                [self hideDelayButton];
            }
        }
        
        // Audio
        if (tabCell.collectionViewType == SQTabMenuCollectionViewTypeAudio) {
            
            if (_lastIndexPathAudio) {
                SQTabMenuCollectionViewCell *lastCell = (SQTabMenuCollectionViewCell *)[_audioTabBarCollectionView cellForItemAtIndexPath:_lastIndexPathAudio];
                lastCell.nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:kAlphaNotFocusedBackground];
            }
            
            tabCell.nameLabel.textColor = [UIColor whiteColor];
            _lastIndexPathAudio = [self.audioTabBarCollectionView indexPathForCell:tabCell];
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(newAudioSelected) object:nil];
            [self performSelector:@selector(newAudioSelected) withObject:nil afterDelay:2.0];
        }
    }
    
}// newItemSelected


- (void) restoreSub
{
    NSString *currentSubs = [[NSUserDefaults standardUserDefaults] valueForKey:@"currentSubs"];
    if (!currentSubs || [currentSubs isEqual:@"off"]) {
        return;
    }
    
    for (Subtitle *sub in _subsTracks) {
        
        NSString *name = [[sub language] lowercaseString];
        
        if ([name isEqual:currentSubs]) {
            NSUInteger row = [_subsTracks indexOfObject:sub];
            _lastIndexPathSubtitle = [NSIndexPath indexPathForRow:row inSection:0];
            [self newSubSelected];
            return;
        }
    }
    
}


- (void) newSubSelected
{
    Subtitle *lastSelected = _subsTracks[_lastIndexPathSubtitle.row];
    
    if (lastSelected.index) {
        [_mediaplayer setCurrentVideoSubTitleIndex:lastSelected.index.intValue];
        self.subtitleTextView.hidden = YES;
        [self stopSubtitleParseTimer];
    } else {
        [_mediaplayer setCurrentVideoSubTitleIndex:-1];
        
        NSString *file = lastSelected.filePath;
        if (file) {
            NSString *string = [self readSubtitleAtPath:file withEncoding:lastSelected.encoding];
            NSError *error;
            SRTParser *parser = [[SRTParser alloc] init];
            _currentSelectedSub = [parser parseString:string error:&error];
        } else {
            if (lastSelected.fileAddress) {
                [lastSelected downloadSubtitle:^(NSString * _Nullable filePath) {
                    NSString *string = [self readSubtitleAtPath:filePath withEncoding:lastSelected.encoding];
                    NSError *error;
                    lastSelected.filePath = filePath;
                    SRTParser *parser = [[SRTParser alloc] init];
                    _currentSelectedSub = [parser parseString:string error:&error];
                }];
            }
        }
    }
    
}

- (NSString *)readSubtitleAtPath:(NSString *)path withEncoding:(NSString *)encoding
{
    
    NSString *string = nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    CFStringEncoding encodingType = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)encoding);
    if (encodingType != kCFStringEncodingInvalidId) {
        CFStringRef cfstring = CFStringCreateWithBytes(kCFAllocatorDefault, data.bytes, data.length, encodingType, YES);
        string = (__bridge NSString *)cfstring;
        CFRelease(cfstring);
        return string;
    }
    
    // Sometimes the encoding is unknown (i.e. Catalan) so we have to fallback on some sort of other check
    [NSString stringEncodingForData:data encodingOptions:nil convertedString:&string usedLossyConversion:nil];
    if (string) {
        return string;
    }
    
    // Just as a last resort failsafe, open in UTF-8. Encoding will probably be broken but it will open.
    string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string;
    
}

- (void) newAudioSelected
{
    NSDictionary *lastSelected = _audioTracks[_lastIndexPathAudio.row];
    [_mediaplayer setCurrentAudioTrackIndex:[lastSelected[@"index"]intValue]];
    
}


- (void) showDelayButton
{
    self.middleSubsConstraint.constant = -280.0;
    self.middleAudioConstraint.constant = 280.0;
    
    [UIView animateWithDuration:0.3 animations:^{
        self.subsDelayButton.alpha = 1.0;
        [self.view layoutIfNeeded];
    }];
}


- (void) hideDelayButton
{
    self.middleSubsConstraint.constant = -140.0;
    self.middleAudioConstraint.constant = 140.0;
    
    [UIView animateWithDuration:0.3 animations:^{
        self.subsDelayButton.alpha = .0;
        [self.view layoutIfNeeded];
    }];
}


#pragma mark - Subtitles Datasource

- (void) createAudioSubsDatasource
{
    NSString *path = [_mediaplayer.media.url.path stringByRemovingPercentEncoding];
    [[SubtitleManager sharedManager] searchWithFile:path completion:^(NSArray<Subtitle *> * _Nullable subtitles) {
        _subsTracks = [NSMutableArray array];
        [_subsTracks addObject:[[Subtitle alloc] initWithLanguage:@"Off" fileAddress:nil fileName:nil encoding:nil]];
        [_subsTracks addObjectsFromArray:subtitles];
        
        // Subtitles Internal
        _subsTrackIndexes = [_mediaplayer videoSubTitlesIndexes];
        NSArray *subsTrackNames = nil;
        @try {
            subsTrackNames = [_mediaplayer videoSubTitlesNames];
        }
        
        @catch (NSException *exception) {
            NSMutableArray *subsTrackNamesMut = [NSMutableArray array];
            for (id item in _subsTrackIndexes) {
                NSString *subsName = [NSString stringWithFormat:@"Subtitle %lu", [_subsTrackIndexes indexOfObject:item]];
                [subsTrackNamesMut addObject:subsName];
            }
            subsTrackNames = [subsTrackNamesMut copy];
        }
        
        if ([_subsTrackIndexes count] == [subsTrackNames count] && [_subsTrackIndexes count] > 1) {
            for (NSUInteger i = 1; i < [_subsTrackIndexes count]; i++) {
                Subtitle *item = [[Subtitle alloc] initWithLanguage:[subsTrackNames objectAtIndex:i] fileAddress:nil fileName:nil encoding:nil];
                item.index = [NSNumber numberWithUnsignedInteger:i];
                [_subsTracks addObject:item];
            }
        }
        
        // Audio
        _audioTracks = [NSMutableArray array];
        NSArray *audioTrackIndexes = [_mediaplayer audioTrackIndexes];
        NSArray *audioTrackNames = nil;
        @try {
            audioTrackNames = [_mediaplayer audioTrackNames];
        }
        
        @catch (NSException *exception) {
            NSMutableArray *audioTrackNamesMut = [NSMutableArray array];
            for (id item in audioTrackIndexes) {
                NSString *audioName = [NSString stringWithFormat:@"Audio %lu", [audioTrackIndexes indexOfObject:item]];
                [audioTrackNamesMut addObject:audioName];
            }
            audioTrackNames = [audioTrackNamesMut copy];
        }
        
        if ([audioTrackIndexes count] == [audioTrackNames count] && [audioTrackIndexes count] > 1) {
            for (NSUInteger i = 1; i < [audioTrackIndexes count]; i++)
                [_audioTracks addObject:@{@"index": [audioTrackIndexes objectAtIndex:i], @"name": [audioTrackNames objectAtIndex:i]}];
        }
        else {
            [_audioTracks addObject:@{@"name" : @"Disabled"}];
        }
        
        _lastIndexPathSubtitle = [NSIndexPath indexPathForRow:0 inSection:0];
        _lastIndexPathAudio    = [NSIndexPath indexPathForRow:0 inSection:0];
        
        self.subTabBarCollectionView.dataSource = self;
        self.subTabBarCollectionView.delegate   = self;
        [self.subTabBarCollectionView reloadData];
        
        self.audioTabBarCollectionView.dataSource = self;
        self.audioTabBarCollectionView.delegate   = self;
        [self.audioTabBarCollectionView reloadData];
        
        [self restoreSub];
    }];
    
    /*
    [[SQClientController shareClient]subtitlesListForHash:_hash
                                                withBlock:^(NSData *data, NSError *error) {
     
                                                    SBJsonParser *parser = [[SBJsonParser alloc]init];
                                                    id object = [parser objectWithData:data];
     
                                                    if (!error && [object isKindOfClass:[NSArray class]]) {
     
     
                                                    }
                                                    else {
                                                        _tryAccount++;
                                                        if (_tryAccount < 10) {
                                                            [self performSelector:@selector(createAudioSubsDatasource)
                                                                       withObject:nil afterDelay:5.0];
                                                        }
                                                    }
                                                }];
     */
    
}// createOptionsRoll


#pragma mark - Subtitles text

- (void) stopSubtitleParseTimer
{
    if (_subtitleTimer.isValid) {
        [_subtitleTimer invalidate];
    }
    
}// stopSubtitleParseTimer:


- (void) resumeSubtitleParseTimerIfNeeded
{
    if (!_subtitleTimer.isValid && (_lastIndexPathSubtitle.row > 0 && _lastIndexPathSubtitle.row < [_subsTracks count] - [_subsTrackIndexes count])) {
        [_subtitleTimer invalidate];
        _subtitleTimer = nil;
        _subtitleTimer = [NSTimer timerWithTimeInterval:0.5
                                                 target:self
                                               selector:@selector(searchAndShowSubtitle)
                                               userInfo:nil
                                                repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:_subtitleTimer forMode:NSDefaultRunLoopMode];
    }
    
}// resumeSubtitleParseTimerIfNeeded


- (void) searchAndShowSubtitle
{
    float currentSeconds = [self currentTimeSeconds] - _offsetFloat;
    
    // Search for timeInterval
    NSPredicate *initialPredicate = [NSPredicate predicateWithFormat:@"(%@ >= SELF.startTime) AND (%@ <= SELF.endTime)", @(currentSeconds), @(currentSeconds)];
    NSArray *objectsFound = [_currentSelectedSub filteredArrayUsingPredicate:initialPredicate];
    SRTSubtitle *lastFounded = (SRTSubtitle *)[objectsFound lastObject];
    
    if (lastFounded) {
        if ([lastFounded.content.lowercaseString containsString:@"opensubtitles"]) {
            return;
        }
        [self updateSubtitle:lastFounded.content];
        
        CGRect rectBack = [lastFounded.content boundingRectWithSize:CGSizeMake(1920, 1080)
                                               options:NSStringDrawingUsesLineFragmentOrigin
                                            attributes:[subSetting attributes]
                                               context:nil];
        

        if (subSetting.backgroundType == SQSubSettingBackgroundBlur) {
            self.widthSubtitleConstraint.constant  = rectBack.size.width + 140;
            self.heightSubtitleConstraint.constant = rectBack.size.height + 34;
            self.backSubtitle.hidden = NO;
        }
        else if (subSetting.backgroundType == SQSubSettingBackgroundNone) {
            self.backSubtitle.hidden = YES;
            self.backSubtitleView.hidden = YES;
        }
        else {
            self.widthSubtitleViewConstraint.constant  = rectBack.size.width + 140;
            self.heightSubtitleViewConstraint.constant = rectBack.size.height + 34;
            self.backSubtitleView.hidden = NO;
        }
       
        self.heightSubtitleTextConstraint.constant = rectBack.size.height + 34;
        [self.view layoutIfNeeded];
        
        self.subtitleTextView.hidden = NO;
        
    } else {
        self.subtitleTextView.hidden = YES;
        self.backSubtitle.hidden = YES;
        self.backSubtitleView.hidden = YES;
    }
    
}// searchAndShowSubtitle


- (float) currentTimeSeconds
{
    float timevlc = (float) [[_mediaplayer time]intValue];
    return timevlc * 0.001;
}


- (void) updateSubtitle:(NSString *) string
{
    /*
    NSShadow *shadow = [[NSShadow alloc]init];
    shadow.shadowOffset = CGSizeMake(.0, 1.0);
    shadow.shadowBlurRadius = 5.0;
    shadow.shadowColor = [UIColor blackColor];
    
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineSpacing = 1.6;
    
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc]initWithString:string];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:_sizeFloat weight:UIFontWeightMedium] range:NSMakeRange(0, string.length)];
    [attr addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor] range:NSMakeRange(0, string.length)];
    [attr addAttribute:NSShadowAttributeName value:shadow range:NSMakeRange(0, string.length)];
    [attr addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, string.length)];
    */

    self.subtitleTextView.attributedText = [[NSAttributedString alloc]initWithString:string attributes:[subSetting attributes]];
}


#pragma mark - Time Custom Methods

- (NSString *)durationAsString
{
    int totalDurationInSeconds = (int) ([[_mediaplayer time]intValue] - [[_mediaplayer remainingTime]intValue]) * 0.001;
    div_t hours = div(totalDurationInSeconds,3600);
    div_t minutes = div(hours.rem,60);
    int seconds = minutes.rem;

    return [NSString stringWithFormat:@"%02d:%02d:%02d", hours.quot, minutes.quot, seconds];
    
}// durationAsString


- (NSString *)durationToEndAsString
{
    int totalDurationInSeconds = (int) [[_mediaplayer remainingTime]intValue] * 0.001;
    div_t hours = div(-totalDurationInSeconds,3600);
    div_t minutes = div(hours.rem,60);
    int seconds = minutes.rem;
    
    return [NSString stringWithFormat:@"-%02d:%02d:%02d", hours.quot, minutes.quot, seconds];
    
}// durationToEndAsString


- (NSString *)currentTimeAsString
{
    int actualSeconds = [[_mediaplayer time]intValue] * 0.001;
    div_t hours = div(actualSeconds,3600);
    div_t minutes = div(hours.rem,60);
    int seconds = minutes.rem;
    
    return [NSString stringWithFormat:@"%02d:%02d:%02d", hours.quot, minutes.quot, seconds];
    
}// currentTimeAsString


- (float) currentTimeAsPercentage
{
    float currentTimeInSeconds  = (float)[[_mediaplayer time]intValue];
    float durationTimeInSeconds = currentTimeInSeconds - (float)[[_mediaplayer remainingTime]intValue];
    if (durationTimeInSeconds == 0 || isnan(durationTimeInSeconds)) {
        return 0;
    }
    
    float result = currentTimeInSeconds/durationTimeInSeconds;
    
    return result;
    
}// currentTimeAsPercentage


- (float) remainingTime
{
    float currentTimeInSeconds = (float)[[_mediaplayer time]intValue];
    float durationTimeInSeconds = currentTimeInSeconds - (float)[[_mediaplayer remainingTime]intValue];
    
    return (durationTimeInSeconds - currentTimeInSeconds) * 0.001;
    
}// remainingTime


- (int) durationInSeconds
{
    int durationTimeInSeconds = [[_mediaplayer time]intValue] * 0.001 - [[_mediaplayer remainingTime]intValue] * 0.001;
    return durationTimeInSeconds;
    
}// durationInSeconds

@end
