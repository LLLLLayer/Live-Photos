# 将实况照片(Live Photos)添加到 APP 中

2015 年，Apple 推出 iPhone 6s 和 iPhone 6s Plus，同时推出了实况照片(Live Photos)功能。在当时，这是一项开创性的、全新的摄影方式，能以动态方式记录精彩瞬间，为静态照片注入生命力。拍摄实况照片时，iPhone 会录下拍照前后各 1.5 秒所发生的一切。用户可以选择不同的封面照片、添加有趣的效果、编辑实况照片，并与家人或朋友进行分享。

本文将介绍 Live Photo 相关技术概念，并使用 Swift 实现 Live Photo 的分解、合成功能。分解和合成的演示如下：

| ![Disassemble](https://raw.githubusercontent.com/LLLLLayer/Galaxy/main/resources/images/live_photos/Disassemble.gif) | ![Asemble](https://raw.githubusercontent.com/LLLLLayer/Galaxy/main/resources/images/live_photos/Asemble.gif) |
| :----------------------------------------------------------: | :----------------------------------------------------------: |
|                将 Live Photo 分解为照片和视频                |           使用(不相关的)照片和视频合成 Live Photo            |

> 文章所有涉及的 API 基于 **iOS 16.0+**，使用了较多 Swift 的结构化并发的相关概念，阅读需要有一定基础。

> 文章项目代码已经开源，欢迎参考[这里](https://github.com/LLLLLayer/Live-Photos)。



## Live Photo 格式

以下是一张曾于武汉大学拍摄的樱花实况照片。我们如果直接将 Live Photo 隔空投送到 Mac，可以得到一张 `HEIC` 格式的照片。但若我们在分享页面，进行**「选项 -> 所有照片数据」**的勾选，那么我们投送后将得到一个文件夹，内部包含一张`HEIC` 格式的照片、一个 `MOV` 格式的视频：

<img src="https://raw.githubusercontent.com/LLLLLayer/Galaxy/main/resources/images/live_photos/LivePhotoGif.gif" alt="LivePhotoGif"  />

<img src="https://raw.githubusercontent.com/LLLLLayer/Galaxy/main/resources/images/live_photos/LivePhotoSave.png" alt="LivePhotoSave" style="zoom:100%;" />

正如我们所见，一张 Live Photo 由配对的两个资源组成，相同的 Identifier 进行配对：



### 具有特殊 Metadata 的 JPEG 图像

图片拥有属性，对于大多数图像文件格式，使用 [`CGImageSource`](https://developer.apple.com/documentation/imageio/cgimagesource) 类型可以有效地读取数据。可以使用 [The Photo Investigator](https://apps.apple.com/us/app/photo-investigator-view-edit/id571574618) 应用查看照片中的所有 Metadata：

![image-20230410011403546](https://raw.githubusercontent.com/LLLLLayer/Galaxy/main/resources/images/live_photos/ThePhotoInvestigator.png)

拍摄照片时，Apple 相机会自动为照片添加不同种类的 Metadata。大多数元数据都很好理解，如位置存储在 GPS Metadata 中、相机信息位于 EXIF Metadata 中。

其中 [`kCGImagePropertyMakerAppleDictionary`](https://developer.apple.com/documentation/imageio/kcgimagepropertymakerappledictionary) 是 Apple 相机拍摄的照片的键值对字典。“17” 是  Maker Apple 中的 LivePhotoVideoIndex，是 Live Photo 的 Identifier Key，完整列表可以参考 [Apple Tags](https://exiftool.org/TagNames/Apple.html)。

Live Photo 需要有特殊 Metadata 的 JPEG 图像：

```
[kCGImagePropertyMakerAppleDictionary : [17 : <Identifier>]]
```



### 具有特殊 Metadata 的 MOV 视频文件

> [默认情况下，Live Photo 捕获使用 H.264 编解码器对 Live Photo 的视频部分进行编码](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/2866560-availablelivephotovideocodectype)。

[`AVAsset`](https://developer.apple.com/documentation/avfoundation/avasset) 是模拟定时视听媒体的类。其本身不是媒体资源(例如 QuickTime 电影或 MP3 音频文件、以及使用 HTTP 实时流式传输 (HLS) 流式传输的媒体等)，但是它可以作为媒体资源的容器。

一个 `AVAsset` 是一个或多个 `AVAssetTrack` 实例的容器对象，它模拟统一类型的媒体轨道。最常用的轨道类型是 `audio` 音频和 `video` 视频，也可能包含补充轨道，如 `closedCaption` 隐藏式字幕、`subtitle`  副标题和 `metadata` 元数据等。

```swift
static let audio: AVMediaType // The media contains audio media.
static let closedCaption: AVMediaType //The media contains closed-caption content.
static let depthData: AVMediaType // The media contains depth data.
static let metadataObject: AVMediaType // The media contains metadata objects.
static let muxed: AVMediaType // The media contains muxed media.
static let subtitle: AVMediaType // The media contains subtitles.
static let text: AVMediaType // The media contains text.
static let timecode: AVMediaType //The media contains a time code.
static let video: AVMediaType // The media contains video.
```

![image-20230415154610857](https://raw.githubusercontent.com/LLLLLayer/Galaxy/main/resources/images/live_photos/image-20230415154610857.png)

`AVAsset` 存储关于其媒体的描述性 Metadata。AVFoundation 通过使 其 `AVMetadataItem ` 类简化了对 Metadata 的处理。最简单的讲，`AVMetadataItem` 的实例是一个键值对，表示单个 Metadata 值，比如电影的标题或专辑的插图。AVFoundation 框架将相关 Metadata 分组到 `keySpace` 中：

- 特定格式的 [`keySpace`](https://developer.apple.com/documentation/coremedia/cmmetadata/metadata_identifier_keyspaces)。AVFoundation 框架定义了几个特定格式的 Metadata，大致与特定容器或文件格式相关，例如 `quickTimeMetadata` 、 `iTunes`、`id3` 等。单个资源可能包含跨多个 `keySpace` 的元数据值。
- Common `keySpace`。有几个常见的元数据值，为了帮助规范化对公共 Metadata 如例如创建日期或描述的访问，提供了一个common `keySpace`，允许访问几个 `keySpace` 共有的一组有限 Metadata 值。



Live Photo 需要 `keySpace` 为  `AVMetadataKeySpace.quickTimeMetadata` 的特定 top-level Metadata：

```swift
["com.apple.quicktime.content.identifier" : <Identifier>]
```

> "com.apple.quicktime.content.identifier" 即 `AVMetadataKey.quickTimeMetadataKeyContentIdentifier`
>
> 这里的 Identifier 同 「具有特殊 Metadata 的 JPEG 图像」的 Identifier。

静止图像的 Timed Metadata Track：

```swift
["MetadataIdentifier" : "mdta/com.apple.quicktime.still-image-time",
"MetadataDataType" : "com.apple.metadata.datatype.int8"]
```

> "MetadataIdentifier" 即 `kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier`
> "mdta" 即 `AVMetadataKeySpace.quickTimeMetadata`
> "MetadataDataType" 即 `kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType`
> "com.apple.metadata.datatype.int8" 即 `kCMMetadataBaseDataType_SInt8`

静止图像的 Timed Metadata Track 的 Metadata，即让系统知道图像在视频 Timeline 中的位置：

```
["com.apple.quicktime.still-image-time" : 0]  
```



## PHLivePhoto 和 PHLivePhotoView

```swift
class PHLivePhoto : NSObject
class PHLivePhotoView : UIView
```

[`PHLivePhoto`](https://developer.apple.com/documentation/photokit/phlivephoto) 是 Live Photo 的可显示表示、代码中的实例。在 iOS 中，我们可以使用此类从用户的相册等地方引用 Live Photo，将 `PHLivePhoto` 分配给 [`PHLivePhotoView`](https://developer.apple.com/documentation/photokit/phlivephotoview)  从而进行显示。`PHLivePhotoView` 提供了显示 Live Photo 的方法，同时提供与相册中相同的交互式播放功能。

`PHLivePhoto` 对于 Live Photo，类似于与 `UIImage` 对于静态图像。`UIImage` 不只是图像的数据文件，而是可以在 `UIImageView` 中显示的即用型图像。`PHLivePhoto` 同样也不只是相册中的  Live Photo 数据资源，而是准备好在 `PHLivePhotoView` 上显示的 Live Photo。

在 iOS 中，我们可以使用 [`UIImagePickerController`](https://developer.apple.com/documentation/uikit/uiimagepickercontroller)、[`PHAsset`](https://developer.apple.com/documentation/photokit/phasset) 和 [`PHImageManager`](https://developer.apple.com/documentation/photokit/phimagemanager) 从用户的相册中获取 Live Photo，或者通过相册资源创建一个 Live Photo。在 iOS 14.0 及以上版本，我们也可以使用 [`PHPickerViewController`](https://developer.apple.com/documentation/photokit/phpickerviewcontroller) 从用户的相册中获取 Live Photo。

**使用 `UIImagePickerController` 的示例代码如下：**

```swift
func pickLivePhoto(_ sender: AnyObject) {
    let imagePicker = UIImagePickerController()
    imagePicker.sourceType = UIImagePickerControllerSourceType.photoLibrary
    imagePicker.allowsEditing = false
    imagePicker.delegate = self
    imagePicker.mediaTypes = [kUTTypeLivePhoto, kUTTypeImage] as [String]
    present(imagePicker, animated: true, completion: nil)
}

// MARK: UIImagePickerControllerDelegate

func imagePickerController(
    _ picker: UIImagePickerController, 
    didFinishPickingMediaWithInfo info: [String : Any]
) {
    guard let mediaType = info[UIImagePickerControllerMediaType] as? NSString,
          mediaType == kUTTypeLivePhoto,
          let livePhoto = info[UIImagePickerControllerLivePhoto] as? PHLivePhoto else {
        return
    }
    livePhotoView.livePhoto = livePhoto
}
```

> 这里需要注意，我们在指定 `mediaTypes` 时，除了 `kUTTypeLivePhoto`，还有 `kUTTypeImage`，否则在运行时将抛出异常：
>
> ```
> *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: 'The Live Photo type cannot be specified without the Image media type'
> terminating with uncaught exception of type NSException
> ```
>
> 这就导致我们通过代理拿到的 `mediaType`，可能并非 `kUTTypeLivePhoto` 而是静态照片 `kUTTypeImage`，需要进行判断或提示。

**使用 `PHAsset` 和 `PHImageManager` 的示例代码如下：**

```swift
let fetchOptions = PHFetchOptions()
fetchOptions.predicate = NSPredicate(
    format: "(mediaSubtype & %d) != 0", 
    PHAssetMediaSubtype.photoLive.rawValue)
let images = PHAsset.fetchAssets(with: .image, options: fetchOptions)
PHImageManager.default().requestLivePhoto(
    for: images.firstObject!,
    targetSize: .zero,
    contentMode: .default,
    options: nil) { [weak self] livePhoto, _ in
    guard let self else { return }
    self.livePhotoView.livePhoto = livePhoto
}
```

**使用 `PHPickerViewController` 的示例代码如下：**

```swift
func pickLivePhoto(_ sender: UIButton) {
    var config = PHPickerConfiguration()
    config.selectionLimit = 1
    config.filter = .any(of: [.livePhotos])
    config.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    present(picker, animated: true, completion: nil)
}

// MARK: - PHPickerViewControllerDelegate

func picker(
    _ picker: PHPickerViewController,
    didFinishPicking results: [PHPickerResult]
) {
    defer { picker.dismiss(animated: true) }
	  guard let itemProvider = results.first?.itemProvider,
          itemProvider.canLoadObject(ofClass: PHLivePhoto.self) else {
        return
    }
    itemProvider.loadObject(ofClass: PHLivePhoto.self) { [weak self] livePhoto, _ in
        Task { @MainActor in
        		guard let self, let livePhoto else { return }
            self.livePhotoView.livePhoto = livePhoto
        }
    }
}
```

`PHPickerResult` 是从相册中选择的 Asset 的类型。其 [`let itemProvider: NSItemProvider`](https://developer.apple.com/documentation/photokit/phpickerresult/3606600-itemprovider) 属性是所选 Asset 的表示。[`NSItemProvider`](https://developer.apple.com/documentation/foundation/nsitemprovider)  用于在进程之间传输数据或文件。`canLoadObject(ofClass:)`指示其是否可以加载指定类的对象。`loadObject(ofClass:completionHandler:) `将异步加载指定类的对象。最终，我们获取到 `livePhoto` 进行展示和分解。

> 这里需要注意 `loadObject(ofClass:)` 的回调并非主线程，需要回到主线程进行 UI 更新。

>  `PHPickerViewController` 内置隐私(无需完整的相册访问权限)、独立进程、支持多选、支持搜索等，详细可以参考 [Meet the new Photos picker](https://developer.apple.com/videos/play/wwdc2020/10652/)。后文的实现将使用该方式。



## 将 Live Photo 分解为照片和视频

在后文代码示例中，我们使用 `actor LivePhotos` 实现 Live Photo 的分解和合成。`LivePhotos` 已提供单例 `sharedInstance`：

```swift
// LivePhotos.swift
actor LivePhotos {
    static let sharedInstance = LivePhotos()
}
```

在示例项目的 `LivePhotosViewController+Disassemble.swift` 中，我们这样使用 `disassemble(livePhoto:)` 来分解 Live Photo：

```swift
func disassemble(livePhoto: PHLivePhoto) {
    Task {
        do {
            // Disassemble the livePhoto
            let (photoURL, videoURL) = try await LivePhotos.sharedInstance.disassemble(livePhoto: livePhoto)
            // Show the photo
            if FileManager.default.fileExists(atPath: photoURL.path) {
                guard let photo = UIImage(contentsOfFile: photoURL.path) else { return }
                await MainActor.run { leftImageView.image = photo }
            }
            // show the video
            if FileManager.default.fileExists(atPath: videoURL.path) {
                playVideo(URL(fileURLWithPath: videoURL.path))
            }
        } catch {
            await MainActor.run { Toast.show("Disassemble failed") }
        }
    }
}
```

在这里我们可以看到，`disassemble(livePhoto:)` 是一个异步函数，且可以抛出错误，因此我们使用 `try await` 调用，并用 `Task {...}` 进行包裹。函数返回两个 URL，分别是图片的 URL 和 视频的 URL，利用这两个 URL 进行展示。如果在分解过程中抛出错误，将进行提示。

接着，我们来看 `disassemble(livePhoto:)` 的具体实现：

```swift
func disassemble(livePhoto: PHLivePhoto) async throws -> (URL, URL) {
  	// 1
    let assetResources = PHAssetResource.assetResources(for: livePhoto)
    // 5
    let list = try await withThrowingTaskGroup(of: (PHAssetResource, Data).self) { taskGroup in
        for assetResource in assetResources {
            taskGroup.addTask {
                // 3
                return try await withCheckedThrowingContinuation { continuation in
                    let dataBuffer = NSMutableData()
                    // 2
                    let options = PHAssetResourceRequestOptions()
                    options.isNetworkAccessAllowed = true                                       
                    PHAssetResourceManager.default().requestData(for: assetResource, options: options) { data in
                        dataBuffer.append(data)
                    } completionHandler: { error in
                        // 4
                        guard error == nil else {
                            continuation.resume(throwing: LivePhotosDisassembleError.requestDataFailed)
                            return
                        }
                        continuation.resume(returning: (assetResource, dataBuffer as Data))
                    }
                }
            }
        }
        // 6
        var results: [(PHAssetResource, Data)] = []
        for try await result in taskGroup {
            results.append(result)
        }
        return results
    }
    // ...
}
```

我们先看这部分代码：

1. [`assetResources(for:)`](https://developer.apple.com/documentation/photokit/phassetresource/1623988-assetresources) 函数返回与 Asset 关联的数据资源列表 `[PHAssetResource]`。由于我们的入参是 `PHLivePhoto` 因此，这里将获得两个资源，我们可以从控制台查看资源类型：

```
(lldb) po assetResources[0].uniformTypeIdentifier
"public.heic"
(lldb) po assetResources[1].uniformTypeIdentifier
"com.apple.quicktime-movie"
```

2. 我们希望将两个资源分别转换成 `Data` 类型的对象，这里使用用 `requestData(for:options:dataReceivedHandler:completionHandler:)` 函数完成。该函数异步的请求指定资产资源的底层数据。我们为 `options`  的 `isNetworkAccessAllowed` 设置为 `true`，指定照片可以从 iCloud 下载。`handler`  提供请求数据的块，我们自行将其组合。`completionHandler` 中，我们获得最终的结果。
3. 由于我们使用异步函数，因此使用  `withCheckedThrowingContinuation(function:_:)` 挂起当前任务，调用闭包，直到得到结果或抛出错误，从而桥接代码到新的并发模型上。
4. 我们使用 `completionHandler` 里的 `error` 参数来为 `continuation` 提供结果或抛出错误。
5. 由于我们有两个资源，我们希望并行处理资源的转换，我们使用 `withThrowingTaskGroup(of:returning:body:)` 启动两个子任务。
6. 我们等待 Task Group 中的子任务完成，返回 `[(PHAssetResource, Data)]` 类型的结果。

我们来看剩下的部分：

```swift
func disassemble(livePhoto: PHLivePhoto) async throws -> (URL, URL) {
    // ...
    // 7
    guard let photo = (list.first { $0.0.type == .photo }),
          let video = (list.first { $0.0.type == .pairedVideo }) else {
        throw LivePhotosDisassembleError.requestDataFailed
    }
    // 8
    let cachesDirectory = try cachesDirectory()
    let photoURL = try save(photo.0, data: photo.1, to: cachesDirectory)
    let videoURL = try save(video.0, data: video.1, to: cachesDirectory)
    return (photoURL, videoURL)
}

private func save(_ assetResource: PHAssetResource, data: Data, to url: URL) throws -> URL {
    // 9
    guard let ext = UTType(assetResource.uniformTypeIdentifier)?.preferredFilenameExtension else {
        throw LivePhotosDisassembleError.noFilenameExtension
    }
    let destinationURL = url.appendingPathComponent(NSUUID().uuidString).appendingPathExtension(ext as String)
    try data.write(to: destinationURL, options: [Data.WritingOptions.atomic])
    return destinationURL
}
```

7. 我们根据 `PHAssetResource` 的 `type` 属性，找到照片元组和视频元组，若未找到则抛出错误。
8. 我们将 `PHAssetResource` 对应的 `Data` 写入缓存文件夹中。
9. `uniformTypeIdentifier` 是资源的统一类型标识符，Apple Inc. 提供的软件上使用的标识符，用于唯一标识给定类别或类型的项目。这里用 `UTType` 的 `init(_:)` 将其转换为 `heic`、`mov` 作为文件的后缀。

至此，我们得到 Live Photo 分解得到的图片和视频 URL，以供展示或保存。



## 使用照片和视频创建 Live Photo

正如前文提到的，创建 Live Photo 需要使用 Identifier 将照片和视频配对。我们要将此 Identifier 添加到照片和视频的 Metadata 中，从而生成有效的 Live Photo。

在示例项目的 `LivePhotosViewController+Asemble.swift` 中，我们将通过以下方式使用创建 Live Photo API：

```swift
func assemble(photo: URL, video: URL) {
    progressView.progress = 0
    Task {
        let livePhoto = try await LivePhotos.sharedInstance.assemble(photoURL:photo, videoURL:video) { [weak self] process in
            guard let self else { return }
            self.progressView.progress = process
        }
        Task { @MainActor in
            self.livePhotoView.livePhoto = livePhoto
        }
    }
}
```

和成 Live Photo 的函数签名如下：

```swift
func assemble(photoURL: URL, videoURL: URL, progress: ((Float) -> Void)? = nil) async throws -> PHLivePhoto
```

入参为 `photoURL`、`videoURL`、进度回调 `progress`，该异步函数最终返回一个 `PHLivePhoto`  对象。

和成总共分为三步：获取处理好的 `pairedPhotoURL`、获取处理好的 `pairedVideoURL`、使用两个 URL 创建 `PHLivePhoto`：

```swift
func assemble(photoURL: URL, videoURL: URL, progress: ((Float) -> Void)? = nil) async throws -> PHLivePhoto {
    let cacheDirectory = try cachesDirectory()
    let identifier = UUID().uuidString
    // 1
    let pairedPhotoURL = addIdentifier(
        identifier,
        fromImageURL: photoURL,
        to: cacheDirectory.appendingPathComponent(identifier).appendingPathExtension("jpg"))
    // 2
    let pairedVideoURL = try await addIdentifier(
        identifier,
        fromVideoURL: videoURL,
        to: cacheDirectory.appendingPathComponent(identifier).appendingPathExtension("mov"),
        progress: progress)
    // 3
    return try await withCheckedThrowingContinuation({ continuation in
        // Create a `PHLivePhoto` with the `pairedPhotoURL` and the `pairedVideoURL`.
    })
}
```



### 将 Metadata 添加到照片

[Image I/O](https://developer.apple.com/documentation/imageio) Framework 允许我们打开一个图像，然后将 Identifier 写入 `kCGImagePropertyMakerAppleDictionary`  一个特殊的属性 Key `17` ：

```swift
private func addIdentifier(
    _ identifier: String, 
    fromPhotoURL photoURL: URL, 
    to destinationURL: URL
) throws -> URL {
          // 1
    guard let imageSource = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
          // 2
          let imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
          // 3
          var imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable : Any] else {
        throw LivePhotosAssembleError.addPhotoIdentifierFailed
    }
    // 4
    let identifierInfo = ["17" : identifier]
    imageProperties[kCGImagePropertyMakerAppleDictionary] = identifierInfo
    // 5
    guard let imageDestination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw LivePhotosAssembleError.createDestinationImageFailed
    }
    // 6
    CGImageDestinationAddImage(imageDestination, imageRef, imageProperties as CFDictionary)
    // 7
    if CGImageDestinationFinalize(imageDestination) {
        return destinationURL
    } else {
        throw LivePhotosAssembleError.createDestinationImageFailed
    }
}
```

在上述代码中：

1. 使用 [`CGImageSourceCreateWithURL(_:_:)`](https://developer.apple.com/documentation/imageio/1465262-cgimagesourcecreatewithurl) 创建从 URL 指定的位置读取的图像源，类型为 [`CGImageSource`](https://developer.apple.com/documentation/imageio/cgimagesource#3702930)，使用该类型可以读取大多数图像文件格式的数据，获取 Metadata 、缩略图等。`url` 参数为图片的 URL；`options` 参数为指定附加创建选项的[字典](https://developer.apple.com/documentation/imageio/cgimagesource#3702930)，如指示是否缓存解码图像、指定是否创建缩略图等。
2. 使用 [`CGImageSourceCreateImageAtIndex(_:_:_:)`](https://developer.apple.com/documentation/imageio/1465011-cgimagesourcecreateimageatindex) 在图像源中指定索引处的数据创建图像对象，类型为 [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage)。`isrc` 参数为包含图像数据的图像源；`index` 为所需图像的从零开始的索引；`options` 为指定附加创建选项的字典。

> 如果我们愿意，也可以通过 `Data` 的方式获取 `imageRef`：
>
> ```swift
> let data = try? Data(contentsOf: imageURL)
> let imageRef = UIImage(data: data)?.cgImage
> ```

3. 使用 [`CGImageSourceCopyPropertiesAtIndex(_:_:_:)`](https://developer.apple.com/documentation/imageio/1465363-cgimagesourcecopypropertiesatind)  返回图像源中指定位置的图像属性，类型为 [`CFDictionary`](https://developer.apple.com/documentation/corefoundation/cfdictionary)。参数同样为 `isrc`、`index`、`options`。

4. 将特殊的 Metadata 写入 `imageProperties` 的 `kCGImagePropertyMakerAppleDictionary` 中。
5. 使用 [`CGImageDestinationCreateWithURL(_:_:_:_:) `](https://developer.apple.com/documentation/imageio/1465361-cgimagedestinationcreatewithurl) 将图像数据写入指定的 URL，返回值类型为 [`CGImageDestination`](https://developer.apple.com/documentation/imageio/cgimagedestination)，提供了一个用于保存图像数据的抽象接口，例如我们可以创建还包含缩略图的图像、可以使用 `CGImageDestination` 向图像添加 Metadata。`url` 是写入图像数据的 URL，此对象会覆盖指定 URL 中的任何数据；`type` 为生成的图像文件的[统一类型标识符](https://developer.apple.com/documentation/uniformtypeidentifiers)，映射到 MIME 和文件类型的通用类型；`count` 是要包含在图像文件中的图像数量；`options` 是预留参数，暂时还没有用，指定为 `nil` 即可。
6. 使用 [`CGImageDestinationAddImage(_:_:_:)`](https://developer.apple.com/documentation/imageio/1464962-cgimagedestinationaddimage) 将图像添加到 `CGImageDestination`，参数 `idst` 是要修改的 `CGImageDestination`、`image` 是要添加的图像、`properties` 是一个可选的字典，指定添加图像的[属性](https://developer.apple.com/documentation/imageio/image_properties/individual_image_properties)。
7. [`CGImageDestinationFinalize(_:)`](https://developer.apple.com/documentation/imageio/1464968-cgimagedestinationfinalize) 是作为保存图像的最后一步，返回保存结果的 `Bool`，在调用此方法之前的输出无效。调用此函数后，我们无法再向 `CGImageDestination` 添加任何数据。



### 将 Metadata 添加到视频

#### 相关类和接口介绍

将这些数据添加到视频中会复杂一些。 我们需要使用 AVFoundation 的 [`AVAssetReader`](https://developer.apple.com/documentation/avfoundation/avassetreader) 、[`AVAssetWriter`](https://developer.apple.com/documentation/avfoundation/avassetwriter) 重写视频。 我们先来简单看下它们的概念和我们将使用到的函数：

**AVAssetReader**

1. `AVAssetReader` 与一个 `AVAsset` 关联，是一个视频对象。需要为 `AVAssetReader` 添加 `AVAssetReaderOutput` 来读取数据，`AVAssetReaderOutput`  同样需要 `AVAssetReader` 才能完成功能。一个 `AVAssetReader` 可以关联多个 `AVAssetReaderOutput`。
2. `AVAssetReaderTrackOutput` 是 `AVAssetReaderOutput` 的子类，是从 `AVAssetTrack` 读取媒体数据的对象。可以通过 `AVAsset ` 指定 `AVMediaType` 的 Track 创建一个`AVAssetReaderTrackOutput` 作为 Track 数据读取器。

3. `assetReader.startReading()` 表示 `AVAssetReaderTrackOutput` 可以开始读取数据了。 它可以是音频数据、视频数据或其他数据。
4. `assetReaderOutput.copyNextSampleBuffer()` 表示读取下一条数据。
5. `assetReader.cancelReading()` 表示停止读取数据。

**AVAssetWriter**

1. `AVAssetWriter` 是写管理器， `AVAssetWriterInput` 是数据写入器。 一个 `AVAssetWriter` 可以有多个 `AVAssetWriterInput`。
2. `assetWriter.startWriting()` 表示 `AVAssetWriterInput` 可以开始写入。
3. `assetWriter.startSession(atSourceTime: .zero)` 表示数据从零秒开始写入。
4. `assetWriterInput.isReadyForMoreMediaData`，一个布尔值，表示输入准备好接受更多媒体数据。
5. 如果有多个 `AVAssetWriterInput`，当其中一个 `AVAssetWriterInput` 填满缓冲区时，数据不会被处理，而是等待其他数据被 `AVAssetWriterInput` 写入相应的时长，然后才会处理数据。



#### 整体步骤

我们合成 Live Photo 的整体步骤如下：

1. 初始化 `AVAssetReader` ，创建对应的 `AVAssetReaderTrackOutput`，包括 `videoReaderOutput`、`audioReaderOutput`。
2. 初始化`AVAssetWriter`，创建及对应的 `AVAssetWriterInput`，包括 `videoWriterInput`、`audioWriterInput`。
3. 使用 `AVAssetWriter` 写入构造好的 Identifier Metadata(只能在入开始前设置)。
4. `AVAssetWriter` 添加来自 `AVAssetWriterInputMetadataAdaptor` 的 `assetWriterInput`。
5. `AVAssetWriter` 进入写状态。
6. 使用 `AVAssetReader` 和 `AVAssetWriterInputMetadataAdaptor` 写入 Timed Metadata Track 的 Metadata。
7. `videoReaderOutput` 、 `audioReaderOutput` 、`videoWriterInput`、`audioWriterInput`进入读写写状态。
8. 一旦 `AVAssetReaderOuput `读取 Track 数据，使用 `AVAssetWriterInput` 写入 Track 数据。
9. 读取完所有数据后，让 `AVAssetReader` 停止读取。 使所有 `AVAssetWriterInput` 标记完成。
10. 等待 `AVAssetWriter` 变为完成状态，视频创建完成。



#### 代码实现

下面我们来看具体代码实现，首先是核心「具有特殊 Metadata 的 MOV 视频文件」的 Mata 部分。

创建一个具有 Identifier 的 Metadata 的 `AVMetadataItem`，这里的 Identifier 与照片的 Identifier 相同：

```swift
private func metadataItem(for identifier: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.keySpace = AVMetadataKeySpace.quickTimeMetadata // "mdta"
    item.dataType = "com.apple.metadata.datatype.UTF-8"
    item.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as any NSCopying & NSObjectProtocol // "com.apple.quicktime.content.identifier"
    item.value = identifier as any NSCopying & NSObjectProtocol
    return item
}
```

创建静止图像的 Timed Metadata Track：

```swift
private func stillImageTimeMetadataAdaptor() -> AVAssetWriterInputMetadataAdaptor {
    let quickTimeMetadataKeySpace = AVMetadataKeySpace.quickTimeMetadata.rawValue // "mdta"
    let stillImageTimeKey = "com.apple.quicktime.still-image-time"
    let spec: [NSString : Any] = [
        kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as NSString : "\(quickTimeMetadataKeySpace)/\(stillImageTimeKey)",
        kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as NSString : kCMMetadataBaseDataType_SInt8]
    var desc : CMFormatDescription? = nil
    CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
        allocator: kCFAllocatorDefault,
        metadataType: kCMMetadataFormatType_Boxed,
        metadataSpecifications: [spec] as CFArray,
        formatDescriptionOut: &desc)
    let input = AVAssetWriterInput(
        mediaType: .metadata,
        outputSettings: nil,
        sourceFormatHint: desc)
    return AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
}
```

创建静止图像的 Timed Metadata Track 的 Metadata：

```swift
private func stillImageTimeMetadataItem() -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.key = "com.apple.quicktime.still-image-time" as any NSCopying & NSObjectProtocol
    item.keySpace = AVMetadataKeySpace.quickTimeMetadata // "mdta"
    item.value = 0 as any NSCopying & NSObjectProtocol
    item.dataType = kCMMetadataBaseDataType_SInt8 as String // "com.apple.metadata.datatype.int8"
    return item
}
```

接着，我们具体来看添加 Identifier 逻辑。首先，我们初始化 `AVAssetReader` ，创建对应的 `AVAssetReaderTrackOutput`，包括 `videoReaderOutput`、`audioReaderOutput`。初始化`AVAssetWriter`，创建及对应的 `AVAssetWriterInput`，包括 `videoWriterInput`、`audioWriterInput`。对应整体步骤的 1、2：

```swift
private func addIdentifier(
    _ identifier: String,
    fromVideoURL videoURL: URL,
    to destinationURL: URL,
    progress: ((Float) -> Void)? = nil
) async throws -> URL {
    let asset = AVURLAsset(url: videoURL)
    
    // --- Reader ---
    
    // Create the video reader
    let videoReader = try AVAssetReader(asset: asset)
    
    // Create the video reader output
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { 
        throw LivePhotosAssembleError.loadTracksFailed
    }
    let videoReaderOutputSettings : [String : Any] = [kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA]
    let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderOutputSettings)
    
    // Add the video reader output to video reader
    videoReader.add(videoReaderOutput)
    
    // Create the audio reader
    let audioReader = try AVAssetReader(asset: asset)
    
    // Create the audio reader output
    guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else { 
        throw LivePhotosAssembleError.loadTracksFailed 
    }
    let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
    
    // Add the audio reader output to audioReader
    audioReader.add(audioReaderOutput)
    
    // --- Writer ---
    
    // Create the asset writer
    let assetWriter = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
    
    // Create the video writer input
    let videoWriterInputOutputSettings : [String : Any] = [
        AVVideoCodecKey : AVVideoCodecType.h264,
        AVVideoWidthKey : try await videoTrack.load(.naturalSize).width,
        AVVideoHeightKey : try await videoTrack.load(.naturalSize).height]
    let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterInputOutputSettings)
    videoWriterInput.transform = try await videoTrack.load(.preferredTransform)
    videoWriterInput.expectsMediaDataInRealTime = true
    
    // Add the video writer input to asset writer
    assetWriter.add(videoWriterInput)
    
    // Create the audio writer input
    let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
    audioWriterInput.expectsMediaDataInRealTime = false
    
    // Add the audio writer input to asset writer
    assetWriter.add(audioWriterInput)
    
    // ...
}
```

接着，我们使用 `AVAssetWriter` 写入构造好的 Identifier Metadata(只能在入开始前设置)。`AVAssetWriter` 添加来自 `AVAssetWriterInputMetadataAdaptor` 的 `assetWriterInput`。`AVAssetWriter` 进入写状态。对应整体步骤的 3、4、5：

```swift
private func addIdentifier(
    _ identifier: String,
    fromVideoURL videoURL: URL,
    to destinationURL: URL,
    progress: ((Float) -> Void)? = nil
) async throws -> URL? {
    // ...
    
    // Create the identifier metadata
    let identifierMetadata = metadataItem(for: identifier)
    // Create still image time metadata track
    let stillImageTimeMetadataAdaptor = stillImageTimeMetadataAdaptor()
    assetWriter.metadata = [identifierMetadata]
    assetWriter.add(stillImageTimeMetadataAdaptor.assetWriterInput)
  
    // Start the asset writer
    assetWriter.startWriting()
    assetWriter.startSession(atSourceTime: .zero)
    
    // ...
}
```

接着，我们使用 `AVAssetReader` 和 `AVAssetWriterInputMetadataAdaptor` 写入 Timed Metadata Track 的 Metadata。对应整体步骤的 6：

```swift
private func addIdentifier(
    _ identifier: String,
    fromVideoURL videoURL: URL,
    to destinationURL: URL,
    progress: ((Float) -> Void)? = nil
) async throws -> URL {
    // ...
    
    let frameCount = try await asset.frameCount()
    let stillImagePercent: Float = 0.5
    await stillImageTimeMetadataAdaptor.append(
        AVTimedMetadataGroup(
            items: [stillImageTimeMetadataItem()],
            timeRange: try asset.makeStillImageTimeRange(percent: stillImagePercent, inFrameCount: frameCount)))
    
    // ...
}
```

> 其中，涉及获取 `AVAsset` 帧数、静止图像 `CMTimeRange` 的方法：
>
> ```swift
> extension AVAsset {
>     func frameCount(exact: Bool = false) async throws -> Int {
>         let videoReader = try AVAssetReader(asset: self)
>         guard let videoTrack = try await self.loadTracks(withMediaType: .video).first else { return 0 }
>         if !exact {
>             async let duration = CMTimeGetSeconds(self.load(.duration))
>             async let nominalFrameRate = Float64(videoTrack.load(.nominalFrameRate))
>             return try await Int(duration * nominalFrameRate)
>         }
>         let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
>         videoReader.add(videoReaderOutput)
>         videoReader.startReading()
>         var frameCount = 0
>         while let _ = videoReaderOutput.copyNextSampleBuffer() {
>             frameCount += 1
>         }
>         videoReader.cancelReading()
>         return frameCount
>     }
>     
>     func makeStillImageTimeRange(percent: Float, inFrameCount: Int = 0) async throws -> CMTimeRange {
>         var time = try await self.load(.duration)
>         var frameCount = inFrameCount
>         if frameCount == 0 {
>             frameCount = try await self.frameCount(exact: true)
>         }
>         let duration = Int64(Float(time.value) / Float(frameCount))
>         time.value = Int64(Float(time.value) * percent)
>         return CMTimeRangeMake(start: time, duration: CMTimeMake(value: duration, timescale: time.timescale))
>     }
> }
> ```

接着`videoReaderOutput` 、 `audioReaderOutput` 、`videoWriterInput`、`audioWriterInput`进入读写写状态。一旦 `AVAssetReaderOuput `读取 Track 数据，使用 `AVAssetWriterInput` 写入 Track 数据。对应整体步骤的 7、8、9：

```swift
private func addIdentifier(
    _ identifier: String,
    fromVideoURL videoURL: URL,
    to destinationURL: URL,
    progress: ((Float) -> Void)? = nil
) async throws -> URL {
    // ...

    async let writingVideoFinished: Bool = withCheckedThrowingContinuation { continuation in
        Task {
            videoReader.startReading()
            var currentFrameCount = 0
            videoWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "videoWriterInputQueue")) {
                while videoWriterInput.isReadyForMoreMediaData {
                    if let sampleBuffer = videoReaderOutput.copyNextSampleBuffer()  {
                        currentFrameCount += 1
                        if let progress {
                            let progressValue = min(Float(currentFrameCount)/Float(frameCount), 1.0)
                            Task { @MainActor in
                                progress(progressValue)
                            }
                        }
                        if !videoWriterInput.append(sampleBuffer) {
                            videoReader.cancelReading()
                            continuation.resume(throwing: LivePhotosAssembleError.writingVideoFailed)
                            return
                        }
                    } else {
                        videoWriterInput.markAsFinished()
                        continuation.resume(returning: true)
                        return
                    }
                }
            }
        }
    }
    
    async let writingAudioFinished: Bool = withCheckedThrowingContinuation { continuation in
        Task {
            audioReader.startReading()
            audioWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audioWriterInputQueue")) {
                while audioWriterInput.isReadyForMoreMediaData {
                    if let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() {
                        if !audioWriterInput.append(sampleBuffer) {
                            audioReader.cancelReading()
                            continuation.resume(throwing: LivePhotosAssembleError.writingAudioFailed)
                            return
                        }
                    } else {
                        audioWriterInput.markAsFinished()
                        continuation.resume(returning: true)
                        return
                    }
                }
            }
        }
    }
  
    await (_, _) = try (writingVideoFinished, writingAudioFinished)
    
    // ...
}
```

最后，等待 `AVAssetWriter` 变为完成状态，视频创建完成。对应整体步骤的 10：

```swift
private func addIdentifier(
    _ identifier: String,
    fromVideoURL videoURL: URL,
    to destinationURL: URL,
    progress: ((Float) -> Void)? = nil
) async throws -> URL? {
    // ...
    
    await assetWriter.finishWriting()
    return destinationURL
    
    // ...
}
```

带有具有特殊 Metadata 的 MOV 视频文件创建完成，可回到「使用照片和视频创建 Live Photo」查看图片、视频的合成。



### 将 Live Photo 保存到本地

我们可以调整下合成 Live Photo 的异步函数，将 `pairedPhotoURL`、`pairedVideoURL` 作为返回值一并返回：

```swift
func assemble(photoURL: URL, videoURL: URL, progress: ((Float) -> Void)? = nil) async throws -> (PHLivePhoto, (URL, URL)) {
    let pairedPhotoURL = // ...
    let pairedVideoURL = // ...
    let livePhoto = // ...
    return (livePhoto, (pairedPhotoURL, pairedVideoURL))
}
```

我们将图片、视频分别保存即可：

```swift
func saveButtonDidSelect(_ sender: UIButton) {
    guard let (photoURL, videURL) = asembleURLs.value,
          let photoURL, let videURL else {
        return
    }
    PHPhotoLibrary.shared().performChanges({
        let creationRequest = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        creationRequest.addResource(with: PHAssetResourceType.photo, fileURL: photoURL, options: options)
        creationRequest.addResource(with: PHAssetResourceType.pairedVideo, fileURL: videURL, options: options)
    }, completionHandler: { success, _ in
        Toast.show(success ? "Saved successfully" : "An error occurred")
    })
}
```





## 参考资料

[1] [Apple Introduces iPhone 6s & iPhone 6s Plus](https://www.apple.com/newsroom/2015/09/09Apple-Introduces-iPhone-6s-iPhone-6s-Plus/)

[2] [Take and edit Live Photos](https://support.apple.com/en-us/HT207310)

[3] [What is the “Maker Apple” Metadata in iPhone Photos?](https://photoinvestigator.co/blog/the-mystery-of-maker-apple-metadata/)

[4] [Displaying Live Photos](https://developer.apple.com/documentation/photokit/displaying_live_photos)

[5] [How to make Live Photo and save it in photo library in iOS.](https://prafullkumar77.medium.com/how-to-make-live-photo-and-save-it-in-photo-library-in-ios-5255cdc2f15d)

[6] [LimitPoint LivePhoto](https://github.com/LimitPoint/LivePhoto)