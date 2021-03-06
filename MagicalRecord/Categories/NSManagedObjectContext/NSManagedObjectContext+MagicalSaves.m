//
//  NSManagedObjectContext+MagicalSaves.m
//  Magical Record
//
//  Created by Saul Mora on 3/9/12.
//  Copyright (c) 2012 Magical Panda Software LLC. All rights reserved.
//

#import "NSManagedObjectContext+MagicalSaves.h"
#import "MagicalRecord+ErrorHandling.h"
#import "NSManagedObjectContext+MagicalRecord.h"
#import "MagicalRecord.h"

@interface NSManagedObjectContext (InternalMagicalSaves)

- (void) MR_saveWithErrorCallback:(void(^)(NSError *))errorCallback;

@end


@implementation NSManagedObjectContext (MagicalSaves)

- (void) MR_saveWithErrorCallback:(void(^)(NSError *))errorCallback;
{
    if (![self hasChanges])
    {
        MRLog(@"NO CHANGES IN CONTEXT %@ - NOT SAVING", [self MR_description]);
        return;
    }
    
    MRLog(@"-> Saving %@", [self MR_description]);

    NSError *error = nil;
	BOOL saved = NO;
	@try
	{
#ifndef _NO_PARENT_CONTEXT        
        // Obtain permanent objectID before saving to workaround the bug
        // that child MOCs don't give saved objects a permanent objectID.
        // https://devforums.apple.com/message/566410
        // Warning: This could affect performance since obtainPermanentIDsForObjects:error:
        // requires transactional access to persistent stores.
        [self obtainPermanentIDsForObjects:[[self insertedObjects] allObjects] error:nil];
#endif        
        saved = [self save:&error];
	}
	@catch (NSException *exception)
	{
		MRLog(@"Unable to perform save: %@", (id)[exception userInfo] ?: (id)[exception reason]);
	}
	@finally 
    {
        if (!saved)
        {
            if (errorCallback)
            {
                errorCallback(error);
            }
            else
            {
                [MagicalRecord handleErrors:error];
            }
        }
    }
}

- (void) MR_saveNestedContexts;
{
    [self MR_saveNestedContextsErrorHandler:nil];
}

- (void) MR_saveNestedContextsErrorHandler:(void (^)(NSError *))errorCallback;
{
    [self performBlockAndWait:^{
        [self MR_saveWithErrorCallback:errorCallback];
    }];
    if (self == [[self class] MR_defaultContext])
    {
        [[[self class] MR_rootSavingContext] MR_saveInBackgroundErrorHandler:errorCallback];
        return;
    }
    [[self parentContext] MR_saveNestedContextsErrorHandler:errorCallback];
}

- (void) MR_save;
{
    [self MR_saveErrorHandler:nil];    
}

- (void) MR_saveErrorHandler:(void (^)(NSError *))errorCallback;
{
    [self performBlockAndWait:^{
        [self MR_saveWithErrorCallback:errorCallback];
    }];
    
    if (self == [[self class] MR_defaultContext])
    {
        [[[self class] MR_rootSavingContext] MR_saveInBackgroundErrorHandler:errorCallback];
    }
}

- (void) MR_saveInBackgroundCompletion:(void (^)(void))completion;
{
    [self MR_saveInBackgroundErrorHandler:nil completion:completion];
}

- (void) MR_saveInBackgroundErrorHandler:(void (^)(NSError *))errorCallback;
{
    [self MR_saveInBackgroundErrorHandler:errorCallback completion:nil];
}

- (void) MR_saveInBackgroundErrorHandler:(void (^)(NSError *))errorCallback completion:(void (^)(void))completion;
{
    [self performBlock:^{
        [self MR_saveWithErrorCallback:errorCallback];

        if (self == [[self class] MR_defaultContext])
        {
            [[[self class] MR_rootSavingContext] MR_saveInBackgroundErrorHandler:errorCallback completion:completion];
            return;
        }

        if (completion || self == [[self class] MR_rootSavingContext])
        {
            if (completion)
            {
                dispatch_async(dispatch_get_main_queue(), completion);
            }
        }
    }];
}

@end
