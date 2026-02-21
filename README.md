# ShineCard iOS

纯 iOS + Metal 实现的光泽卡片效果。

## 技术栈

- **SwiftUI** - UI 层
- **Metal** - GPU 渲染
- **自定义 Shader** - 实时光泽效果

## 效果

- ✨ 触摸跟随的光泽
- 🌈 彩虹全息反射
- 🎴 3D 卡片呈现
- ⚡ 60fps 流畅渲染

## 项目结构

```
ShineCard-iOS/
├── ShineCard/
│   ├── ShineCardApp.swift      # App 入口
│   ├── ContentView.swift       # 主界面
│   ├── ShineCardView.swift     # Metal 视图桥接
│   ├── ShineCardRenderer.swift # Metal 渲染器
│   ├── ShineShader.metal       # Metal Shader
│   └── Info.plist
└── project.yml                 # XcodeGen 配置
```

## 运行方式

### 方式 1：XcodeGen（推荐）

```bash
cd ShineCard-iOS

# 安装 XcodeGen（如果没有）
brew install xcodegen

# 生成 Xcode 项目
xcodegen generate

# 打开项目
open ShineCard.xcodeproj
```

### 方式 2：手动创建 Xcode 项目

1. 打开 Xcode
2. 创建新 iOS App 项目
3. 将 `ShineCard/` 文件夹中的文件拖入项目
4. 确保添加 `ShineShader.metal` 到编译目标
5. 运行

## 要求

- iOS 15.0+
- Xcode 15.0+
- 支持 Metal 的设备（iPhone 6s 及以上）

## 原理

### Metal Shader

```metal
// 片段着色器计算光泽
float shineIntensity = smoothstep(shineRadius, 0.0, dist);
float3 finalColor = mix(color.rgb, shineColor, shineIntensity * 0.4);
```

- 根据触摸点距离计算光泽强度
- 使用 `smoothstep` 实现平滑过渡
- 添加彩虹色相偏移

### 渲染流程

1. SwiftUI `ContentView` 包含 `ShineCardView`
2. `ShineCardView` 是 `UIViewRepresentable`，桥接到 `MTKView`
3. `ShineCardRenderer` 处理 Metal 渲染
4. Shader 接收触摸位置，实时计算光泽效果

## 扩展

可以添加的效果：
- [ ] 加载真实图片作为卡片纹理
- [ ] 更多 shader 效果（镜面反射、折射）
- [ ] 3D 卡片翻转动画
- [ ] 多卡片网格布局

## 相关

- [shine-card-web](https://github.com/muvich3n/shine-card-web) - Web 版本（CSS 模拟）
- [shine-card](https://github.com/muvich3n/shine-card) - React Native 版本（WebGPU）

## License

MIT
