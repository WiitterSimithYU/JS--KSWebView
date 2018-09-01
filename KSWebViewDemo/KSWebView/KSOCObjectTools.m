//
//  KSOCObjectTools.m
//  KSWebViewDemo
//
//  Created by kinsun on 2018/8/27.
//  Copyright © 2018年 kinsun. All rights reserved.
//

#import "KSOCObjectTools.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface _KSOCMethodModel : NSObject

@property (nonatomic, assign, readonly) SEL selector;
@property (nonatomic, copy, readonly) NSString *selectorString;
@property (nonatomic, assign, readonly, getter=isClassMethod) BOOL classMethod;

@end

@implementation _KSOCMethodModel

-(instancetype)initWithMethod:(Method)method classMethod:(BOOL)isClassMethod {
    if (self = [super init]) {
        SEL selector = method_getName(method);
        _selector = selector;
        _selectorString = NSStringFromSelector(selector);
        _classMethod = isClassMethod;
    }
    return self;
}

@end

@interface _KSOCObject : NSObject

@property (nonatomic, strong, readonly) id objectValue;
@property (nonatomic, assign, readonly) void *locationValue;
@property (nonatomic, assign, readonly) BOOL isObject;

@end

@implementation _KSOCObject

+(instancetype)objectFromValue:(id)objectValue {
    _KSOCObject *object = [[_KSOCObject alloc]init];
    object->_objectValue = objectValue;
    object->_isObject = YES;
    return object;
}

+(instancetype)locationFromValue:(void *)locationValue {
    _KSOCObject *object = [[_KSOCObject alloc]init];
    object->_locationValue = locationValue;
    object->_isObject = NO;
    return object;
}

-(void)dealloc {
    _objectValue = nil;
    _locationValue = NULL;
}

@end

@interface _KSOCClassInfoModel : NSObject

@property (nonatomic, strong) NSDictionary <NSString*, _KSOCMethodModel*>*classMethod;
@property (nonatomic, strong) NSDictionary <NSString*, _KSOCMethodModel*>*instanceMethod;

@end

@implementation _KSOCClassInfoModel @end

#import "GOModel.h"

@interface _KSOCInvokeModel : GOModel

@property (nonatomic, copy) NSString *objKey;
@property (nonatomic, copy) NSString *funcName;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, strong) NSMutableArray *params;

@end

@implementation _KSOCInvokeModel @end

static NSString *k_colon            = @":";
static NSString *k_empty            = @"";
static NSString *k_location_format  = @"%p";
static NSString *k_class            = @"class";
static NSString *k_instance         = @"instance";
static NSString *k_objKey           = @"objKey";
static NSString *k_className        = @"className";
static NSString *k_value            = @"value";
static NSString *k_type             = @"type";
static NSString *k_other            = @"other";
static NSString *k_object           = @"object";
static NSString *k_string           = @"string";
static NSString *k_bool             = @"bool";
static NSString *k_float            = @"float";
static NSString *k_double           = @"double";
static NSString *k_int              = @"int";
static NSString *k_uint             = @"uint";
static NSString *k_long             = @"long";
static NSString *k_ulong            = @"ulong";
static NSString *k_longlong         = @"longlong";
static NSString *k_ulonglong        = @"ulonglong";

#import <WebKit/WKScriptMessage.h>
#import "KSWebViewScriptHandler.h"
#import "MJExtension.h"

@interface KSOCObjectTools ()

@property (nonatomic, strong, readonly) NSMutableDictionary <NSString *, _KSOCClassInfoModel*>*catalog;
@property (nonatomic, strong, readonly) NSMutableDictionary <NSString *, _KSOCObject*>*objectPool;

@end

@implementation KSOCObjectTools
@synthesize catalog = _catalog, objectPool = _objectPool;

static KSOCObjectTools *_instance = nil;
+(instancetype)share {
    if (_instance == nil) {
        _instance = [[self alloc]init];
    }
    return _instance;
}

- (NSMutableDictionary<NSString *, _KSOCClassInfoModel*>*)catalog {
    if (!_catalog) {
        _catalog = [NSMutableDictionary dictionary];
    }
    return _catalog;
}

- (NSMutableDictionary<NSString *,_KSOCObject*> *)objectPool {
    if (!_objectPool) {
        _objectPool = [NSMutableDictionary dictionary];
    }
    return _objectPool;
}

+(NSString*)scriptHandlerImportClass:(WKScriptMessage*)message {
    NSString *body = message.body;
    if (body.length) {
        Class class = NSClassFromString(body);
        if (class) {
            NSMutableDictionary <NSString *,_KSOCClassInfoModel*>*catalog = [KSOCObjectTools share].catalog;
            NSMutableArray <NSString*>* classMethodNameArray = [NSMutableArray array];
            NSMutableArray <NSString*>* instanceMethodNameArray = [NSMutableArray array];
            while (class != nil) {
                NSString *classNameKey = NSStringFromClass(class);
                _KSOCClassInfoModel *info = [catalog objectForKey:classNameKey];
                if (!info) {
                    info = [self methodFromClass:class];
                    [catalog setObject:info forKey:classNameKey];
                }
                [classMethodNameArray addObjectsFromArray:info.classMethod.allKeys];
                [instanceMethodNameArray addObjectsFromArray:info.instanceMethod.allKeys];
                class = [class superclass];
            }
            NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:classMethodNameArray, k_class, instanceMethodNameArray, k_instance, nil];
            NSString *json = [dict mj_JSONString];
            return json;
        }
    }
    return nil;
}

+(_KSOCClassInfoModel*)methodFromClass:(Class)class {
    NSMutableDictionary <NSString *,_KSOCMethodModel *>* instanceMethod = [NSMutableDictionary dictionary];
    unsigned int count;
    Method *instance_methods = class_copyMethodList(class, &count);
    for (int i = 0; i < count; i++) {
        Method method = instance_methods[i];
        _KSOCMethodModel *model = [[_KSOCMethodModel alloc]initWithMethod:method classMethod:NO];
        NSString *key = [model.selectorString stringByReplacingOccurrencesOfString:k_colon withString:k_empty];
        [instanceMethod setValue:model forKey:key];
    }
    NSMutableDictionary <NSString *,_KSOCMethodModel *>* classMethod = [NSMutableDictionary dictionary];
    Class metaClass = object_getClass(class);
    Method *class_methods = class_copyMethodList(metaClass, &count);
    for (int i = 0; i < count; i++) {
        Method method = class_methods[i];
        _KSOCMethodModel *model = [[_KSOCMethodModel alloc]initWithMethod:method classMethod:YES];
        NSString *key = [model.selectorString stringByReplacingOccurrencesOfString:k_colon withString:k_empty];
        [classMethod setValue:model forKey:key];
    }
    _KSOCClassInfoModel *model = [[_KSOCClassInfoModel alloc]init];
    model.classMethod = classMethod;
    model.instanceMethod = instanceMethod;
    return model;
}

+(NSString*)scriptHandlerInvokeClassMethod:(WKScriptMessage*)message {
    NSString *body = message.body;
    if (body.length) {
        _KSOCInvokeModel *model = [_KSOCInvokeModel objectWithKeyValues:body];
        NSString *funcName = model.funcName;
        NSString *className = model.className;
        NSString *objKey = model.objKey;
        KSOCObjectTools *tools = [KSOCObjectTools share];
        NSMutableDictionary <NSString *, _KSOCObject*>*objectPool = tools.objectPool;
        SEL selector = nil;
        id target = nil;
        NSMethodSignature *signature = nil;
        if (className.length != 0) {
            Class class = NSClassFromString(model.className);
            _KSOCMethodModel *obj_model = [self searchClass:class isClass:YES method:funcName inCatalog:tools.catalog];
            selector = obj_model.selector;
            signature = [class methodSignatureForSelector:selector];
            target = class;
        } else if (objKey.length != 0) {
            _KSOCObject *obj = [objectPool objectForKey:objKey];
            target = obj.objectValue;
            Class class = [target class];
            _KSOCMethodModel *obj_model = [self searchClass:class isClass:NO method:funcName inCatalog:tools.catalog];
            selector = obj_model.selector;
            signature = [class instanceMethodSignatureForSelector:selector];
        }
        if (selector != nil && target != nil) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.selector = selector;
            NSArray *params = model.params;
            for (NSInteger i = 0; i < params.count; i++) {
                void *paramLocation = NULL;
                id param = [params objectAtIndex:i];
                if (param == [NSNull null]) {
                    param = nil;
                } else if ([param isKindOfClass:NSDictionary.class]) {
                    NSDictionary *dict = param;
                    NSString *objKey = [dict objectForKey:k_objKey];
                    if (objKey != nil) {
                        _KSOCObject *obj = [objectPool objectForKey:objKey];
                        if (obj.isObject) {
                            param = obj.objectValue;
                        } else {
                            paramLocation  = obj.locationValue;
                        }
                    }
                } else if ([param isKindOfClass:NSNumber.class]) {
                    NSNumber *number = param;
                    const char *returnType = number.objCType;
                    if (!strcmp(returnType, @encode(signed char))) {
                        BOOL value = number.boolValue;
                        paramLocation = &value;
                    } else if (!strcmp(returnType, @encode(float))) {
                        float value = number.floatValue;
                        paramLocation = &value;
                    } else if (!strcmp(returnType, @encode(double))) {
                        double value = number.doubleValue;
                        paramLocation = &value;
                    } else if (!strcmp(returnType, @encode(int))) {
                        int value = number.intValue;
                        paramLocation = &value;
                    } else if (!strcmp(returnType, @encode(unsigned int))) {
                        unsigned int value = number.unsignedIntValue;
                        paramLocation = &value;
                    } else if (!strcmp(returnType, @encode(long))) {
                        long value = number.longValue;
                        paramLocation = &value;
                    } else if (!strcmp(returnType, @encode(unsigned long))) {
                        unsigned long value = number.unsignedLongValue;
                        paramLocation = &value;
                    } else if (!strcmp(returnType, @encode(long long))) {
                        long long value = number.longLongValue;
                        paramLocation = &value;
                    } else if (!strcmp(returnType, @encode(unsigned long long))) {
                        unsigned long long value = number.unsignedLongLongValue;
                        paramLocation = &value;
                    }
                }
                if (paramLocation == NULL) paramLocation = &param;
                [invocation setArgument:paramLocation atIndex:i+2];
            }
            [invocation retainArguments];
            [invocation invokeWithTarget:target];
            const char *returnType = signature.methodReturnType;
            if (strcmp(returnType, @encode(void))) {
                NSDictionary *returnData = nil;
                if (!strcmp(returnType, @encode(id))) {
                    __unsafe_unretained id returnValue = nil;
                    [invocation getReturnValue:&returnValue];
                    if ([returnValue isKindOfClass:NSString.class]) {
                        returnData = @{k_type: k_string, k_value: returnValue};
                    } else {
                        _KSOCObject *returnObj = [_KSOCObject objectFromValue:returnValue];
                        NSString *key = [NSString stringWithFormat:k_location_format, returnValue];
                        [objectPool setObject:returnObj forKey:key];
                        returnData = @{k_type: k_object, k_className: NSStringFromClass([returnValue class]), k_objKey: key};
                    }
                } else {
                    NSUInteger length = signature.methodReturnLength;
                    void *buffer = (void *)malloc(length);
                    [invocation getReturnValue:buffer];
                    if (!strcmp(returnType, @encode(BOOL))) {
                        NSNumber *value = [NSNumber numberWithBool:*((BOOL*)buffer)];
                        returnData = @{k_type: k_bool, k_value: value};
                    } else if (!strcmp(returnType, @encode(float))) {
                        NSNumber *value = [NSNumber numberWithFloat:*((float*)buffer)];
                        returnData = @{k_type: k_float, k_value: value};
                    } else if (!strcmp(returnType, @encode(double))) {
                        NSNumber *value = [NSNumber numberWithDouble:*((double*)buffer)];
                        returnData = @{k_type: k_double, k_value: value};
                    } else if (!strcmp(returnType, @encode(int))) {
                        NSNumber *value = [NSNumber numberWithInt:*((int*)buffer)];
                        returnData = @{k_type: k_int, k_value: value};
                    } else if (!strcmp(returnType, @encode(unsigned int))) {
                        NSNumber *value = [NSNumber numberWithUnsignedInt:*((unsigned int*)buffer)];
                        returnData = @{k_type: k_uint, k_value: value};
                    } else if (!strcmp(returnType, @encode(long))) {
                        NSNumber *value = [NSNumber numberWithLong:*((long*)buffer)];
                        returnData = @{k_type: k_long, k_value: value};
                    } else if (!strcmp(returnType, @encode(unsigned long))) {
                        NSNumber *value = [NSNumber numberWithUnsignedLong:*((unsigned long*)buffer)];
                        returnData = @{k_type: k_ulong, k_value: value};
                    } else if (!strcmp(returnType, @encode(long long))) {
                        NSNumber *value = [NSNumber numberWithLongLong:*((long long*)buffer)];
                        returnData = @{k_type: k_longlong, k_value: value};
                    } else if (!strcmp(returnType, @encode(unsigned long long))) {
                        NSNumber *value = [NSNumber numberWithUnsignedLongLong:*((unsigned long long*)buffer)];
                        returnData = @{k_type: k_ulonglong, k_value: value};
                    } else {
                        _KSOCObject *returnObj = [_KSOCObject locationFromValue:buffer];
                        NSString *key = [NSString stringWithFormat:k_location_format, buffer];
                        [objectPool setObject:returnObj forKey:key];
                        returnData = @{k_type: k_other, k_objKey: key};
                    }
                }
                if (returnData) {
                    return returnData.mj_JSONString;
                }
            }
        }
    }
    return nil;
}

+(_KSOCMethodModel*)searchClass:(Class)class isClass:(BOOL)isclass method:(NSString*)methodString inCatalog:(NSDictionary <NSString *, _KSOCClassInfoModel*>*)catalog {
    _KSOCClassInfoModel *info = [catalog objectForKey:NSStringFromClass(class)];
    _KSOCMethodModel *model = isclass ? [info.classMethod objectForKey:methodString] : [info.instanceMethod objectForKey:methodString];
    if (model != nil) {
        return model;
    } else {
        return [self searchClass:[class superclass] isClass:isclass method:methodString inCatalog:catalog];
    }
}

+(void)releaseObjects {
    [[KSOCObjectTools share].objectPool removeAllObjects];
}

static NSString *k_initJavaScriptString = nil;

+(NSString *)initJavaScriptString {
    if (k_initJavaScriptString == nil) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"KSOCObjectTools" ofType:@"js"];
        NSString *string = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        k_initJavaScriptString = string;
    }
    return k_initJavaScriptString;
}

static NSDictionary *k_scriptHandlers = nil;

+ (NSDictionary<NSString *,KSWebViewScriptHandler *> *)scriptHandlers {
    if (!k_scriptHandlers) {
        Class class = self.class;
        KSWebViewScriptHandler *importClass = [KSWebViewScriptHandler scriptHandlerWithTarget:class action:@selector(scriptHandlerImportClass:)];
        KSWebViewScriptHandler *invokeMethod = [KSWebViewScriptHandler scriptHandlerWithTarget:class action:@selector(scriptHandlerInvokeClassMethod:)];
        KSWebViewScriptHandler *releaseObjects = [KSWebViewScriptHandler scriptHandlerWithTarget:class action:@selector(releaseObjects)];
        k_scriptHandlers = @{@"__ks_importClass": importClass, @"__ks_invokeMethod": invokeMethod, @"__ks_releaseObjects": releaseObjects};
    }
    return k_scriptHandlers;
}

@end
