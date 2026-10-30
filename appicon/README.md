一次性构建：GitHub 云端 Mac 用 actool 把 HupuAppIcon.xcassets（Single Size, Any/Dark/Tinted, 1024）编译为 Assets.car。
PNG 以 base64 文本存放（连接器只能推文本），workflow 会先解码再编译。结果分别提交到 results-xcode16 / results-xcode26 分支。构建完本分支与结果分支一并删除。
