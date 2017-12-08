//
//  BugsnagSessionTracker.m
//  Bugsnag
//
//  Created by Jamie Lynch on 24/11/2017.
//  Copyright © 2017 Bugsnag. All rights reserved.
//

#import "BugsnagSessionTracker.h"
#import "BugsnagSessionFileStore.h"
#import "BSG_KSLogger.h"
#import "BugsnagSessionTrackingPayload.h"
#import "BugsnagSessionTrackingApiClient.h"

@interface BugsnagSessionTracker ()
@property BugsnagConfiguration *config;
@property BugsnagSessionFileStore *sessionStore;
@property BugsnagSessionTrackingApiClient *apiClient;
@end

@implementation BugsnagSessionTracker

- (instancetype)initWithConfig:(BugsnagConfiguration *)config
                     apiClient:(BugsnagSessionTrackingApiClient *)apiClient {
    if (self = [super init]) {
        self.config = config;
        self.apiClient = apiClient;

        NSString *bundleName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
        NSString *storePath = [BugsnagFileStore findReportStorePath:@"Sessions"
                                                         bundleName:bundleName];
        if (!storePath) {
            BSG_KSLOG_ERROR(@"Failed to initialize session store.");
        }
        _sessionStore = [BugsnagSessionFileStore storeWithPath:storePath];
    }
    return self;
}

- (void)startNewSession:(NSDate *)date
               withUser:(BugsnagUser *)user
           autoCaptured:(BOOL)autoCaptured {

    _currentSession = [[BugsnagSession alloc] initWithId:[[NSUUID UUID] UUIDString]
                                                startDate:date
                                                     user:user
                                             autoCaptured:autoCaptured];

    if (self.config.shouldAutoCaptureSessions || !autoCaptured) {
        [self.sessionStore write:self.currentSession];
    }
    _isInForeground = YES;

    if (self.callback) {
        self.callback(self.currentSession);
    }
}

- (void)suspendCurrentSession:(NSDate *)date {
    _isInForeground = NO;
}

- (void)incrementHandledError {
    @synchronized (self.currentSession) {
        self.currentSession.handledCount++;
        if (self.callback) {
            self.callback(self.currentSession);
        }
    }
}

- (void)send {
    @synchronized (self.sessionStore) {
        NSMutableArray *sessions = [NSMutableArray new];
        NSArray *fileIds = [self.sessionStore fileIds];

        for (NSDictionary *dict in [self.sessionStore allFiles]) {
            [sessions addObject:[[BugsnagSession alloc] initWithDictionary:dict]];
        }
        BugsnagSessionTrackingPayload *payload = [[BugsnagSessionTrackingPayload alloc] initWithSessions:sessions];

        if (payload.sessions.count > 0) {
            [self.apiClient sendData:payload
                         withPayload:[payload toJson]
                               toURL:self.config.sessionEndpoint
                             headers:self.config.sessionApiHeaders
                        onCompletion:^(id data, BOOL success, NSError *error) {

                            if (success && error == nil) {
                                NSLog(@"Sent sessions to Bugsnag");

                                for (NSString *fileId in fileIds) {
                                    [self.sessionStore deleteFileWithId:fileId];
                                }
                            } else {
                                NSLog(@"Failed to send sessions to Bugsnag: %@", error);
                            }
                        }];
        }
    }
}

@end