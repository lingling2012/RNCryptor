//
//  RNCryptTests.m
//
//  Copyright (c) 2012 Rob Napier
//
//  This code is licensed under the MIT License:
//
//  Permission is hereby granted, free of charge, to any person obtaining a 
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//

#import "RNCryptorTests.h"
#import "RNEncryptor.h"
#import "RNDecryptor.h"

NSString *const kGoodPassword = @"Passw0rd!";
NSString *const kBadPassword = @"NotThePassword";

@interface RNCryptorTests () <NSURLConnectionDataDelegate>
@property (nonatomic, readwrite, assign) BOOL isTestRunning;
@property (nonatomic, readwrite, strong) RNEncryptor *encryptor;
@end

@implementation RNCryptorTests

- (void)setUp
{
  [super setUp];

  // Set-up code here.
}

- (void)tearDown
{
  // Tear-down code here.

  [super tearDown];
}

- (void)testSimple
{
  NSData *data = [RNCryptor randomDataOfLength:1024];
  NSError *error;

  NSData *encryptedData = [RNEncryptor encryptData:data
                                      withSettings:kRNCryptorAES256Settings
                                          password:kGoodPassword
                                             error:&error];

  STAssertNil(error, @"Encryption error:%@", error);
  STAssertNotNil(encryptedData, @"Data did not encrypt.");

  NSError *decryptionError;
  NSData *decryptedData = [RNDecryptor decryptData:encryptedData withPassword:kGoodPassword error:&decryptionError];
  STAssertNil(decryptionError, @"Error decrypting:%@", decryptionError);
  STAssertEqualObjects(decryptedData, data, @"Incorrect decryption.");
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
  NSLog(@"didReciveData");
  [self.encryptor addData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
  NSLog(@"didFailWithError:%@", error);
  self.isTestRunning = NO;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
  NSLog(@"didFinishLoading");
  [self.encryptor finish];
}

- (void)testAsync
{
  NSURL *testURL = [NSURL URLWithString:@"http://robnapier.net/favicon.ico"];
  NSError *downloadError;
  NSData *plaintext = [NSData dataWithContentsOfURL:testURL options:0 error:&downloadError];
  STAssertNotNil(plaintext, @"Couldn't download: %@", downloadError);

  NSURLRequest *request = [NSURLRequest requestWithURL:testURL];
  NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
  NSLog(@"Started connection", connection);

  self.isTestRunning = YES;
  __block NSMutableData *encryptedData = [NSMutableData data];
  __block NSError *encryptionError;
  self.encryptor = [[RNEncryptor alloc] initWithSettings:kRNCryptorAES256Settings
                                                password:kGoodPassword
                                                 handler:^(RNCryptor *cryptor, NSData *data) {
                                                   NSLog(@"handler");
                                                   [encryptedData appendData:data];
                                                   if (cryptor.isFinished) {
                                                     encryptionError = cryptor.error;
                                                     self.isTestRunning = NO;
                                                   }
                                                 }];

  NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:10];
  do {
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:timeout];
  } while (self.isTestRunning);

  STAssertFalse(self.isTestRunning, @"Test timed out.");
  STAssertNil(encryptionError, @"Encrypt error: %@", encryptionError);
  STAssertTrue([encryptedData length] > 0, @"Failed to encrypt.");

  NSError *decryptionError;
  NSData *decryptedData = [RNDecryptor decryptData:encryptedData withPassword:kGoodPassword error:&decryptionError];
  STAssertNil(decryptionError, @"decryption error:%@", decryptionError);
  STAssertEqualObjects(plaintext, decryptedData, @"Bad decryption");
}

- (void)testSimpleFail
{
  NSData *data = [RNCryptor randomDataOfLength:1024];
  NSError *error;

  NSData *encryptedData = [RNEncryptor encryptData:data
                                      withSettings:kRNCryptorAES256Settings
                                          password:kGoodPassword
                                             error:&error];

  STAssertNil(error, @"Encryption error:%@", error);
  STAssertNotNil(encryptedData, @"Data did not encrypt.");

  NSError *decryptionError;
  NSData *decryptedData = [RNDecryptor decryptData:encryptedData withPassword:kBadPassword error:&decryptionError];
  STAssertNotNil(decryptionError, @"Should have received error decrypting:%@", decryptionError);
  STAssertNil(decryptedData, @"Decryption should be nil: %@", decryptedData);
}

- (void)testCorruption
{
  NSData *data = [RNCryptor randomDataOfLength:1024];
  NSError *error;

  NSData *encryptedData = [RNEncryptor encryptData:data
                                      withSettings:kRNCryptorAES256Settings
                                          password:kGoodPassword
                                             error:&error];

  STAssertNil(error, @"Encryption error:%@", error);
  STAssertNotNil(encryptedData, @"Data did not encrypt.");

  NSMutableData *corruptData = [encryptedData mutableCopy];
  [corruptData replaceBytesInRange:NSMakeRange(100, 100) withBytes:[[RNCryptor randomDataOfLength:100] bytes]];


  NSError *decryptionError;
  NSData *decryptedData = [RNDecryptor decryptData:encryptedData withPassword:kBadPassword error:&decryptionError];
  STAssertNil(decryptedData, @"Decryption should be nil: %@", decryptedData);
  STAssertEquals([decryptionError code], kRNCryptorHMACMismatch, @"Should have received kRNCryptorHMACMismatch");
}

- (void)testBadHeader
{
  NSData *data = [@"Data" dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error;
  NSMutableData *encrypted = [[RNEncryptor encryptData:data withSettings:kRNCryptorAES256Settings password:kGoodPassword error:&error] mutableCopy];

  uint8_t firstByte = 1;
  [encrypted replaceBytesInRange:NSMakeRange(0, 1) withBytes:&firstByte];

  NSData *decrypted = [RNDecryptor decryptData:encrypted withPassword:kGoodPassword error:&error];
  STAssertNil(decrypted, @"Decrypt should have failed");
  STAssertEquals([error code], kRNCryptorUnknownHeader, @"Wrong error code:%d", [error code]);
}

- (void)testActuallyEncrypting
{
  NSData *data = [@"Data" dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error;
  NSData *encrypted = [RNEncryptor encryptData:data withSettings:kRNCryptorAES256Settings password:kGoodPassword error:&error];

  NSRange found = [encrypted rangeOfData:data options:0 range:NSMakeRange(0, encrypted.length)];
  STAssertEquals(found.location, (NSUInteger)NSNotFound, @"Data is not encrypted");
}

- (void)testBackground
{
  NSData *data = [RNCryptor randomDataOfLength:1024];

  __block NSError *error;
  __block NSData *encryptedData;

  dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    encryptedData = [RNEncryptor encryptData:data
                                withSettings:kRNCryptorAES256Settings
                                    password:kGoodPassword
                                       error:&error];
  });

  STAssertNil(error, @"Encryption error:%@", error);
  STAssertNotNil(encryptedData, @"Data did not encrypt.");

  NSError *decryptionError;
  NSData *decryptedData = [RNDecryptor decryptData:encryptedData withPassword:kGoodPassword error:&decryptionError];
  STAssertNil(decryptionError, @"Error decrypting:%@", decryptionError);
  STAssertEqualObjects(decryptedData, data, @"Incorrect decryption.");
}

//
//- (void)_testDataOfLength:(NSUInteger)length encryptPassword:(NSString *)encryptPassword decryptPassword:(NSString *)decryptPassword
//{
//  RNCryptor *cryptor = [RNCryptor AES256Cryptor];
//
//  NSData *data = [[cryptor class] randomDataOfLength:length];
//
//  NSError *error;
//
//  NSData *encryptedData = [cryptor encryptData:data password:encryptPassword error:&error];
//  NSData *decryptedData = [cryptor decryptData:encryptedData password:decryptPassword error:&error];
//
//  if ([encryptPassword isEqualToString:decryptPassword]) {
//    STAssertTrue([data isEqualToData:decryptedData], @"Decrypted data does not match for length:%d", length); // Don't use STAssertEqualObjects(). Some data is quite large.
//  }
//  else {
//    STAssertFalse([data isEqualToData:decryptedData], @"Decrypt should have failed for length:%d", length); // Don't use STAssertEqualObjects(). Some data is quite large.
//  }
//}
//
//- (void)_testDataOfLength:(NSUInteger)length
//{
//  [self _testDataOfLength:length encryptPassword:kGoodPassword decryptPassword:kBadPassword];
//}
//
//- (void)testData
//{
//  [self _testDataOfLength:1024];
//}

//
//- (NSString *)temporaryFilePath
//{
//  // Thanks to Matt Gallagher
//  NSString *tempFileTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"RNCryptorTest.XXXXXX"];
//  const char *tempFileTemplateCString = [tempFileTemplate fileSystemRepresentation];
//  char *tempFileNameCString = (char *)malloc(strlen(tempFileTemplateCString) + 1);
//  strcpy(tempFileNameCString, tempFileTemplateCString);
//  int fileDescriptor = mkstemp(tempFileNameCString);
//
//  NSAssert(fileDescriptor >= 0, @"Failed to create temporary file");
//
//  NSString *tempFileName =
//      [[NSFileManager defaultManager]
//          stringWithFileSystemRepresentation:tempFileNameCString
//                                      length:strlen(tempFileNameCString)];
//
//  free(tempFileNameCString);
//  return tempFileName;
//}
//
//- (void)_testURLWithLength:(NSUInteger)length encryptPassword:(NSString *)encryptPassword decryptPassword:(NSString *)decryptPassword
//{
//  RNCryptor *cryptor = [RNCryptor AES256Cryptor];
//
//  NSData *data = [[cryptor class] randomDataOfLength:length];
//  NSError *error;
//
//  NSURL *plaintextURL = [NSURL fileURLWithPath:[self temporaryFilePath]];
//  NSURL *ciphertextURL = [NSURL fileURLWithPath:[self temporaryFilePath]];
//  NSURL *decryptedURL = [NSURL fileURLWithPath:[self temporaryFilePath]];
//
//  NSAssert([data writeToURL:plaintextURL options:0 error:&error], @"Couldn't write file:%@", error);
//
//  STAssertTrue([cryptor encryptFromURL:plaintextURL toURL:ciphertextURL append:NO password:encryptPassword error:&error], @"Failed to encrypt:%@", error);
//
//  BOOL result = [cryptor decryptFromURL:ciphertextURL toURL:decryptedURL append:NO password:decryptPassword error:&error];
//  if ([encryptPassword isEqualToString:decryptPassword]) {
//    STAssertTrue(result, @"Failed to decrypt:%@", error);
//    NSData *decryptedData = [NSData dataWithContentsOfURL:decryptedURL];
//    STAssertEqualObjects(data, decryptedData, @"Data doesn't match");
//
//  }
//  else {
//    STAssertFalse(result, @"Should have failed");
//  }
//
//  [[NSFileManager defaultManager] removeItemAtURL:plaintextURL error:&error];
//  [[NSFileManager defaultManager] removeItemAtURL:ciphertextURL error:&error];
//  [[NSFileManager defaultManager] removeItemAtURL:decryptedURL error:&error];
//}
//
//- (void)_testURLWithLength:(NSUInteger)length
//{
//  return [self _testURLWithLength:length encryptPassword:kGoodPassword decryptPassword:kGoodPassword];
//}
//
//
//- (void)testURL
//{
//  [self _testURLWithLength:1024];
//
//}
//
//- (void)testBigData
//{
//  [self _testDataOfLength:1024 * 1024];
//}
//
//- (void)testOddSizeData
//{
//  [self _testDataOfLength:1023];
//  [self _testDataOfLength:1025];
//}
//
//- (void)testActuallyEncrypting
//{
//  NSData *data = [@"Data" dataUsingEncoding:NSUTF8StringEncoding];
//  NSError *error;
//  NSData *encrypted = [[RNCryptor AES256Cryptor] encryptData:data password:kGoodPassword error:&error];
//
//  NSRange found = [encrypted rangeOfData:data options:0 range:NSMakeRange(0, encrypted.length)];
//  STAssertEquals(found.location, (NSUInteger)NSNotFound, @"Data is not encrypted");
//}
//
//- (void)testSmall
//{
//  for (NSUInteger i = 1; i < 32; i++) {
//    [self _testDataOfLength:i];
//  }
//}
//
//- (void)testNearReadBlocksize
//{
//  for (NSUInteger i = 1024 - 10; i < 1024 + 10; i++) {
//    [self _testDataOfLength:i];
//  }
//}
//
//- (void)testNearDoubleReadBlocksize
//{
//  for (NSUInteger i = 2048 - 10; i < 2048 + 10; i++) {
//    [self _testDataOfLength:i];
//  }
//}
//
//- (void)testSmallBadPassword
//{
//  for (NSUInteger i = 1; i < 32; i++) {
//    [self _testDataOfLength:i encryptPassword:kGoodPassword decryptPassword:kBadPassword];
//  }
//}
//
//- (void)testNearReadBlocksizeBadPassword
//{
//  for (NSUInteger i = 1024 - 32; i < 1024 + 32; i++) {
//    [self _testDataOfLength:i encryptPassword:kGoodPassword decryptPassword:kBadPassword];
//  }
//}
//
//- (void)testNearDoubleReadBlocksizeBadPassword
//{
//  for (NSUInteger i = 2048 - 32; i < 2048 + 32; i++) {
//    [self _testDataOfLength:i encryptPassword:kGoodPassword decryptPassword:kBadPassword];
//  }
//}
//
//- (void)testNearTripleReadBlocksizeBadPassword
//{
//  for (NSUInteger i = 3072 - 32; i <= 3072 + 32; i++) {
//    [self _testDataOfLength:i encryptPassword:kGoodPassword decryptPassword:kBadPassword];
//  }
//}
//
//- (void)testURLBadPassword
//{
//  [self _testURLWithLength:1024 encryptPassword:kGoodPassword decryptPassword:kBadPassword];
//}
//
//- (void)testURLSmallBadPassword
//{
//  for (NSUInteger i = 1; i < 32; i++) {
//    [self _testURLWithLength:i encryptPassword:kGoodPassword decryptPassword:kBadPassword];
//  }
//}
//
//- (void)testURLNearReadBlocksize
//{
//  for (NSUInteger i = 1024 - 32; i < 1024 + 32; i++) {
//    [self _testURLWithLength:i];
//  }
//}
//
//- (void)testURLNearReadBlocksizeBadPassword
//{
//  for (NSUInteger i = 1024 - 32; i < 1024 + 32; i++) {
//    [self _testURLWithLength:i encryptPassword:kGoodPassword decryptPassword:kBadPassword];
//  }
//}
//
//// echo Test data | openssl enc -aes-256-cbc -out test.enc -k Passw0rd
//
//static NSString *const kOpenSSLString = @"Test data\n";
//static NSString *const kOpenSSLPath = @"test.enc";
//static NSString *const kOpenSSLPassword = @"Passw0rd";
//
//- (void)testOpenSSLDecrypt
//{
//  NSInputStream *input = [NSInputStream inputStreamWithFileAtPath:kOpenSSLPath];
//  NSOutputStream *output = [NSOutputStream outputStreamToMemory];
//  NSError *error;
//  STAssertTrue([[[RNOpenSSLCryptor alloc] init] decryptFromStream:input toStream:output password:kOpenSSLPassword error:&error], @"Could not decrypt:%@", error);
//
//  NSData *decryptedData = [output propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
//  NSString *decryptedString = [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding];
//  STAssertEqualObjects(decryptedString, kOpenSSLString, @"Decrypted data does not match");
//}
//
//- (void)testOpenSSLEncrypt
//{
//  NSInputStream *input = [NSInputStream inputStreamWithData:[kOpenSSLString dataUsingEncoding:NSUTF8StringEncoding]];
//  NSOutputStream *output = [NSOutputStream outputStreamToMemory];
//  NSError *error;
//  STAssertTrue([[[RNOpenSSLCryptor alloc] init] encryptFromStream:input toStream:output password:kOpenSSLPassword error:&error], @"Could not decrypt:%@", error);
//
//  NSData *encryptedData = [output propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
//
//  NSString *encryptedFile = [self temporaryFilePath];
//  NSString *decryptedFile = [self temporaryFilePath];
//  [encryptedData writeToFile:encryptedFile atomically:NO];
//
//  NSString *cmd = [NSString stringWithFormat:@"/usr/bin/openssl enc -d -aes-256-cbc -k %@ -in %@ -out %@", kOpenSSLPassword, encryptedFile, decryptedFile];
//  STAssertEquals(system([cmd UTF8String]), 0, @"System calll failed");
//
//  NSString *decryptedString = [NSString stringWithContentsOfFile:decryptedFile encoding:NSUTF8StringEncoding error:&error];
//  STAssertEqualObjects(decryptedString, kOpenSSLString, @"Decryption doesn't match: %@", error);
//}
//
//- (void)testURLNegativeInput
//{
//  RNCryptor *cryptor = [RNCryptor AES256Cryptor];
//
//  NSError *error;
//
//  NSURL *plaintextURL = [NSURL fileURLWithPath:@"DoesNotExist"];
//  NSURL *ciphertextURL = [NSURL fileURLWithPath:[self temporaryFilePath]];
//  NSURL *decryptedURL = [NSURL fileURLWithPath:[self temporaryFilePath]];
//
//  // Don't write the data
//
//  STAssertFalse([cryptor encryptFromURL:plaintextURL toURL:ciphertextURL append:NO password:kGoodPassword error:&error], @"Should have failed.");
//
//  [[NSFileManager defaultManager] removeItemAtURL:plaintextURL error:&error];
//  [[NSFileManager defaultManager] removeItemAtURL:ciphertextURL error:&error];
//  [[NSFileManager defaultManager] removeItemAtURL:decryptedURL error:&error];
//}

@end
