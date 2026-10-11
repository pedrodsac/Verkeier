#import "WalkingEngineLogging.h"
#import <Foundation/Foundation.h>
#include <valhalla/midgard/logging.h>

void VKConfigurePedestrianLogging(void) {
#ifndef DEBUG
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The public null logger avoids timestamp formatting, a global stdout
        // lock, and flushing for every native route. Configure is first-use-only.
        valhalla::midgard::logging::Configure({{"type", ""}});
    });
#endif
}
