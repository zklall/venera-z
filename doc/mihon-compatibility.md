# Mihon 漫画源兼容

Android 端从原有漫画源页面接入，不另设漫画源分区：

- **从链接添加**：可输入 JS 漫画源地址或扩展仓库地址。
- **导入文件**：可导入 JS 配置、扩展 APK，或包含索引地址的仓库描述文件。
- **源仓库**：统一管理仓库；点开仓库后搜索、筛选语言、安装或更新漫画源。
- 已安装的源统一显示；点击名称展开设置，更多菜单提供编辑配置、更新和删除。

支持 Mihon/Tachiyomi API 1.4 和 1.6 的常规 HTTP 漫画源，接入搜索、热门、详情、章节、图片、原生源设置和更新流程。扩展的自定义搜索筛选器暂未映射到 Venera 的搜索选项。依赖宿主私有接口或更新网络库接口的扩展可能需要进一步适配，不承诺所有扩展都能运行。

兼容旧 JSON 索引、新版 `repo.json`、Protobuf 索引、独立扩展列表及 gzip。Keiyoushi 的旧 `index.min.json` 会优先通过仓库描述文件寻找新版索引，不把旧版升级提示当成完整源列表。

扩展 APK 保存在应用私有目录，不安装为独立 Android 应用。更新检查扩展包名、签名和版本；加载失败时保留原文件。网络请求及图片使用扩展自身客户端，接入宿主 HTTP 代理、DNS 覆盖和网站验证 Cookie；暂不支持 TLS 连接到代理服务器。阅读历史、下载和无痕模式沿用原有流程。

## 维护

- `android/mihon-runtime`：宿主 API、扩展加载和原生偏好设置。上游快照及许可证见该目录 `NOTICE`、`LICENSE`。
- `android/mihon-fixture`：只供测试的扩展，不进入正式发布附件。
- `MihonRuntimeTest`：本地 HTTP 测试源验证 APK 工厂加载、搜索、章节顺序、图片请求、重启与卸载。可通过 `-PrealMihonApk=/path/to/extension.apk` 增加真实扩展加载检查；它不等于验证该网站的在线服务。

运行 Android 仪器测试时，添加 `-Pandroid.testInstrumentationRunnerArguments.class=com.github.veneraz.mihon.MihonRuntimeTest` 直接指定测试类，避免扫描所有宿主依赖。

发布前使用 `tool/check_android_type_signatures.py` 检查实际 APK，确认 Injekt 类型令牌的泛型签名经过 R8 压缩后仍保留；此检查已接入 Android 发布工作流。

测试扩展不声明兼容所有网站。具体验证结果以当次测试日志为准。
