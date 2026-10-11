#ifdef __cplusplus
extern "C" {
#endif
/// Configure Valhalla before its first actor is constructed. App diagnostics and
/// thrown native errors remain available; Release omits per-route stdout tracing.
void VKConfigurePedestrianLogging(void);
#ifdef __cplusplus
}
#endif
