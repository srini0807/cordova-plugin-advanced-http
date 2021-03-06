#import "CordovaHttpPlugin.h"
#import "CDVFile.h"
#import "TextResponseSerializer.h"
#import "TextRequestSerializer.h"
#import "AFHTTPSessionManager.h"

@interface CordovaHttpPlugin()

- (void)setRequestHeaders:(NSDictionary*)headers forManager:(AFHTTPSessionManager*)manager;
- (void)handleSuccess:(NSMutableDictionary*)dictionary withResponse:(NSHTTPURLResponse*)response andData:(id)data;
- (void)handleError:(NSMutableDictionary*)dictionary withResponse:(NSHTTPURLResponse*)response error:(NSError*)error;
- (NSNumber*)getStatusCode:(NSError*) error;
- (NSMutableDictionary*)copyHeaderFields:(NSDictionary*)headerFields;
- (void)setTimeout:(NSTimeInterval)timeout forManager:(AFHTTPSessionManager*)manager;
- (void)setRedirect:(AFHTTPSessionManager*)manager;

@end

@implementation CordovaHttpPlugin {
    AFSecurityPolicy *securityPolicy;
    bool redirect;
    NSURLCredential *x509Credentials;
    NSURLSessionAuthChallengeDisposition (^authenticationChallengeBlock)(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential);
}

- (void)pluginInitialize {
    securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
    redirect = true;
    authenticationChallengeBlock=^NSURLSessionAuthChallengeDisposition(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential)  {
        
        if ([[[challenge protectionSpace] authenticationMethod] isEqualToString: NSURLAuthenticationMethodClientCertificate]) {
            *credential = x509Credentials;
            if (credential) {
                return NSURLSessionAuthChallengeUseCredential;
            } else {
                return NSURLSessionAuthChallengePerformDefaultHandling;
            }
        } if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            if ([securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
                if (credential) {
                    return NSURLSessionAuthChallengeUseCredential;
                } else {
                    return NSURLSessionAuthChallengePerformDefaultHandling;
                }
            } else {
                return NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            return NSURLSessionAuthChallengePerformDefaultHandling;
        }
    };
}

- (void)setRequestSerializer:(NSString*)serializerName forManager:(AFHTTPSessionManager*)manager {
    if ([serializerName isEqualToString:@"json"]) {
        manager.requestSerializer = [AFJSONRequestSerializer serializer];
    } else if ([serializerName isEqualToString:@"utf8"]) {
        manager.requestSerializer = [TextRequestSerializer serializer];
    } else {
        manager.requestSerializer = [AFHTTPRequestSerializer serializer];
    }
}

- (void)setRequestHeaders:(NSDictionary*)headers forManager:(AFHTTPSessionManager*)manager {
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [manager.requestSerializer setValue:obj forHTTPHeaderField:key];
    }];
}

- (void)setRedirect:(AFHTTPSessionManager*)manager {
    [manager setTaskWillPerformHTTPRedirectionBlock:^NSURLRequest * _Nonnull(NSURLSession * _Nonnull session, NSURLSessionTask * _Nonnull task, NSURLResponse * _Nonnull response, NSURLRequest * _Nonnull request) {
        if (redirect) {
            return request;
        } else {
            return nil;
        }
    }];
}

- (void)handleSuccess:(NSMutableDictionary*)dictionary withResponse:(NSHTTPURLResponse*)response andData:(id)data {
    if (response != nil) {
        [dictionary setValue:response.URL.absoluteString forKey:@"url"];
        [dictionary setObject:[NSNumber numberWithInt:(int)response.statusCode] forKey:@"status"];
        [dictionary setObject:[self copyHeaderFields:response.allHeaderFields] forKey:@"headers"];
    }

    if (data != nil) {
        [dictionary setObject:data forKey:@"data"];
    }
}

- (void)handleError:(NSMutableDictionary*)dictionary withResponse:(NSHTTPURLResponse*)response error:(NSError*)error {
    if (response != nil) {
        [dictionary setValue:response.URL.absoluteString forKey:@"url"];
        [dictionary setObject:[NSNumber numberWithInt:(int)response.statusCode] forKey:@"status"];
        [dictionary setObject:[self copyHeaderFields:response.allHeaderFields] forKey:@"headers"];
        if (error.userInfo[AFNetworkingOperationFailingURLResponseBodyKey]) {
            [dictionary setObject:error.userInfo[AFNetworkingOperationFailingURLResponseBodyKey] forKey:@"error"];
        }
    } else {
        [dictionary setObject:[self getStatusCode:error] forKey:@"status"];
        [dictionary setObject:[error localizedDescription] forKey:@"error"];
    }
}

- (void)handleException:(NSException*)exception withCommand:(CDVInvokedUrlCommand*)command {
  CordovaHttpPlugin* __weak weakSelf = self;

  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  [dictionary setValue:exception.userInfo forKey:@"error"];
  [dictionary setObject:[NSNumber numberWithInt:-1] forKey:@"status"];

  CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
  [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (NSNumber*)getStatusCode:(NSError*) error {
    switch ([error code]) {
        case -1001:
            // timeout
            return [NSNumber numberWithInt:1];
        case -1002:
            // unsupported URL
            return [NSNumber numberWithInt:2];
        case -1003:
            // server not found
            return [NSNumber numberWithInt:0];
        case -1009:
            // no connection
            return [NSNumber numberWithInt:3];
        default:
            return [NSNumber numberWithInt:-1];
    }
}

- (NSMutableDictionary*)copyHeaderFields:(NSDictionary *)headerFields {
    NSMutableDictionary *headerFieldsCopy = [[NSMutableDictionary alloc] initWithCapacity:headerFields.count];
    NSString *headerKeyCopy;

    for (NSString *headerKey in headerFields.allKeys) {
        headerKeyCopy = [[headerKey mutableCopy] lowercaseString];
        [headerFieldsCopy setValue:[headerFields objectForKey:headerKey] forKey:headerKeyCopy];
    }

    return headerFieldsCopy;
}

- (void)setTimeout:(NSTimeInterval)timeout forManager:(AFHTTPSessionManager*)manager {
    [manager.requestSerializer setTimeoutInterval:timeout];
}

- (void)enableSSLPinning:(CDVInvokedUrlCommand*)command {
    bool enable = [[command.arguments objectAtIndex:0] boolValue];

    if (enable) {
        securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate];
    } else {
        securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
    }

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)disableRedirect:(CDVInvokedUrlCommand*)command {
    CDVPluginResult* pluginResult = nil;
    bool disable = [[command.arguments objectAtIndex:0] boolValue];

    redirect = !disable;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}
- (void)setX509AuthClientCredentials:(CDVInvokedUrlCommand*)command {
    NSData *pkcs12Container = [command.arguments objectAtIndex:0];
    NSString *password = [command.arguments objectAtIndex:1];
    CFStringRef passwordRef = (__bridge CFStringRef) password;
    const void *keys[] = { kSecImportExportPassphrase };
    const void *values[] = { passwordRef };
    CFDictionaryRef optionsDictionary = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    CFArrayRef p12Items;
    
    OSStatus result = SecPKCS12Import((__bridge CFDataRef)pkcs12Container, optionsDictionary, &p12Items);
    
    if(result == noErr) {
        CFDictionaryRef identityDict = CFArrayGetValueAtIndex(p12Items, 0);
        SecIdentityRef identityApp =(SecIdentityRef)CFDictionaryGetValue(identityDict,kSecImportItemIdentity);
        
        SecCertificateRef certRef;
        SecIdentityCopyCertificate(identityApp, &certRef);
        
        SecCertificateRef certArray[1] = { certRef };
        CFArrayRef clientCerts = CFArrayCreate(NULL, (void *)certArray, 1, NULL);
        CFRelease(certRef);
        
        x509Credentials = [NSURLCredential credentialWithIdentity:identityApp certificates:(__bridge NSArray *)clientCerts persistence:NSURLCredentialPersistencePermanent];
        CFRelease(clientCerts);
    }
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}
- (void)resetX509AuthClientCredentials:(CDVInvokedUrlCommand*)command {
    x509Credentials = nil;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}
- (void)acceptAllCerts:(CDVInvokedUrlCommand*)command {
    CDVPluginResult* pluginResult = nil;
    bool allow = [[command.arguments objectAtIndex:0] boolValue];

    securityPolicy.allowInvalidCertificates = allow;
    securityPolicy.validatesDomainName = !allow;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)post:(CDVInvokedUrlCommand*)command {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.securityPolicy = securityPolicy;
    [manager setSessionDidReceiveAuthenticationChallengeBlock:authenticationChallengeBlock];

    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *parameters = [command.arguments objectAtIndex:1];
    NSString *serializerName = [command.arguments objectAtIndex:2];
    NSDictionary *headers = [command.arguments objectAtIndex:3];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:4] doubleValue];

    [self setRequestSerializer: serializerName forManager: manager];
    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect: manager];

    CordovaHttpPlugin* __weak weakSelf = self;
    manager.responseSerializer = [TextResponseSerializer serializer];

    @try {
        [manager POST:url parameters:parameters progress:nil success:^(NSURLSessionTask *task, id responseObject) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:responseObject];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } failure:^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }
    @catch (NSException *exception) {
        [self handleException:exception withCommand:command];
    }
}

- (void)get:(CDVInvokedUrlCommand*)command {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.securityPolicy = securityPolicy;
    [manager setSessionDidReceiveAuthenticationChallengeBlock:authenticationChallengeBlock];

    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *parameters = [command.arguments objectAtIndex:1];
    NSDictionary *headers = [command.arguments objectAtIndex:2];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:3] doubleValue];


    [self setRequestSerializer: @"default" forManager: manager];
    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect: manager];

    CordovaHttpPlugin* __weak weakSelf = self;
    manager.responseSerializer = [TextResponseSerializer serializer];

    @try {
        [manager GET:url parameters:parameters progress:nil success:^(NSURLSessionTask *task, id responseObject) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:responseObject];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } failure:^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }
    @catch (NSException *exception) {
        [self handleException:exception withCommand:command];
    }
}

- (void)put:(CDVInvokedUrlCommand*)command {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.securityPolicy = securityPolicy;
    [manager setSessionDidReceiveAuthenticationChallengeBlock:authenticationChallengeBlock];

    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *parameters = [command.arguments objectAtIndex:1];
    NSString *serializerName = [command.arguments objectAtIndex:2];
    NSDictionary *headers = [command.arguments objectAtIndex:3];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:4] doubleValue];

    [self setRequestSerializer: serializerName forManager: manager];
    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect: manager];

    CordovaHttpPlugin* __weak weakSelf = self;
    manager.responseSerializer = [TextResponseSerializer serializer];

    @try {
        [manager PUT:url parameters:parameters success:^(NSURLSessionTask *task, id responseObject) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:responseObject];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } failure:^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }
    @catch (NSException *exception) {
        [self handleException:exception withCommand:command];
    }
}

- (void)patch:(CDVInvokedUrlCommand*)command {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.securityPolicy = securityPolicy;
    [manager setSessionDidReceiveAuthenticationChallengeBlock:authenticationChallengeBlock];

    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *parameters = [command.arguments objectAtIndex:1];
    NSString *serializerName = [command.arguments objectAtIndex:2];
    NSDictionary *headers = [command.arguments objectAtIndex:3];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:4] doubleValue];

    [self setRequestSerializer: serializerName forManager: manager];
    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect: manager];

    CordovaHttpPlugin* __weak weakSelf = self;
    manager.responseSerializer = [TextResponseSerializer serializer];

    @try {
        [manager PATCH:url parameters:parameters success:^(NSURLSessionTask *task, id responseObject) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:responseObject];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } failure:^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }
    @catch (NSException *exception) {
        [self handleException:exception withCommand:command];
    }
}

- (void)delete:(CDVInvokedUrlCommand*)command {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.securityPolicy = securityPolicy;
    [manager setSessionDidReceiveAuthenticationChallengeBlock:authenticationChallengeBlock];

    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *parameters = [command.arguments objectAtIndex:1];
    NSDictionary *headers = [command.arguments objectAtIndex:2];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:3] doubleValue];

    [self setRequestSerializer: @"default" forManager: manager];
    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect: manager];

    CordovaHttpPlugin* __weak weakSelf = self;
    manager.responseSerializer = [TextResponseSerializer serializer];

    @try {
        [manager DELETE:url parameters:parameters success:^(NSURLSessionTask *task, id responseObject) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:responseObject];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } failure:^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }
    @catch (NSException *exception) {
        [self handleException:exception withCommand:command];
    }
}

- (void)head:(CDVInvokedUrlCommand*)command {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.securityPolicy = securityPolicy;
    [manager setSessionDidReceiveAuthenticationChallengeBlock:authenticationChallengeBlock];
    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *parameters = [command.arguments objectAtIndex:1];
    NSDictionary *headers = [command.arguments objectAtIndex:2];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:3] doubleValue];

    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect: manager];

    CordovaHttpPlugin* __weak weakSelf = self;
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];

    @try {
        [manager HEAD:url parameters:parameters success:^(NSURLSessionTask *task) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            // no 'body' for HEAD request, omitting 'data'
            [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:nil];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } failure:^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }
    @catch (NSException *exception) {
        [self handleException:exception withCommand:command];
    }
}

- (void)uploadFile:(CDVInvokedUrlCommand*)command {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.securityPolicy = securityPolicy;
    [manager setSessionDidReceiveAuthenticationChallengeBlock:authenticationChallengeBlock];

    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *parameters = [command.arguments objectAtIndex:1];
    NSDictionary *headers = [command.arguments objectAtIndex:2];
    NSString *filePath = [command.arguments objectAtIndex: 3];
    NSString *name = [command.arguments objectAtIndex: 4];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:5] doubleValue];

    NSURL *fileURL = [NSURL URLWithString: filePath];

    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect: manager];

    CordovaHttpPlugin* __weak weakSelf = self;
    manager.responseSerializer = [TextResponseSerializer serializer];

    @try {
        [manager POST:url parameters:parameters constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
            NSError *error;
            [formData appendPartWithFileURL:fileURL name:name error:&error];
            if (error) {
                NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
                [dictionary setObject:[NSNumber numberWithInt:500] forKey:@"status"];
                [dictionary setObject:@"Could not add file to post body." forKey:@"error"];
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                return;
            }
        } progress:nil success:^(NSURLSessionTask *task, id responseObject) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:responseObject];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } failure:^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }
    @catch (NSException *exception) {
        [self handleException:exception withCommand:command];
    }
}


- (void)downloadFile:(CDVInvokedUrlCommand*)command {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.securityPolicy = securityPolicy;
    [manager setSessionDidReceiveAuthenticationChallengeBlock:authenticationChallengeBlock];

    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *parameters = [command.arguments objectAtIndex:1];
    NSDictionary *headers = [command.arguments objectAtIndex:2];
    NSString *filePath = [command.arguments objectAtIndex: 3];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:4] doubleValue];

    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect: manager];

    if ([filePath hasPrefix:@"file://"]) {
        filePath = [filePath substringFromIndex:7];
    }

    CordovaHttpPlugin* __weak weakSelf = self;
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];

    @try {
        [manager GET:url parameters:parameters progress:nil success:^(NSURLSessionTask *task, id responseObject) {
            /*
             *
             * Licensed to the Apache Software Foundation (ASF) under one
             * or more contributor license agreements.  See the NOTICE file
             * distributed with this work for additional information
             * regarding copyright ownership.  The ASF licenses this file
             * to you under the Apache License, Version 2.0 (the
             * "License"); you may not use this file except in compliance
             * with the License.  You may obtain a copy of the License at
             *
             *   http://www.apache.org/licenses/LICENSE-2.0
             *
             * Unless required by applicable law or agreed to in writing,
             * software distributed under the License is distributed on an
             * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
             * KIND, either express or implied.  See the License for the
             * specific language governing permissions and limitations
             * under the License.
             *
             * Modified by Andrew Stephan for Sync OnSet
             *
             */
            // Download response is okay; begin streaming output to file
            NSString* parentPath = [filePath stringByDeletingLastPathComponent];

            // create parent directories if needed
            NSError *error;
            if ([[NSFileManager defaultManager] createDirectoryAtPath:parentPath withIntermediateDirectories:YES attributes:nil error:&error] == NO) {
                NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
                [dictionary setObject:[NSNumber numberWithInt:500] forKey:@"status"];
                if (error) {
                    [dictionary setObject:[NSString stringWithFormat:@"Could not create path to save downloaded file: %@", [error localizedDescription]] forKey:@"error"];
                } else {
                    [dictionary setObject:@"Could not create path to save downloaded file" forKey:@"error"];
                }
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                return;
            }
            NSData *data = (NSData *)responseObject;
            if (![data writeToFile:filePath atomically:YES]) {
                NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
                [dictionary setObject:[NSNumber numberWithInt:500] forKey:@"status"];
                [dictionary setObject:@"Could not write the data to the given filePath." forKey:@"error"];
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                return;
            }

            id filePlugin = [self.commandDelegate getCommandInstance:@"File"];
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:nil];
            [dictionary setObject:[filePlugin getDirectoryEntry:filePath isDirectory:NO] forKey:@"file"];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } failure:^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];
            [dictionary setObject:@"There was an error downloading the file" forKey:@"error"];

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }
    @catch (NSException *exception) {
        [self handleException:exception withCommand:command];
    }
}

@end
