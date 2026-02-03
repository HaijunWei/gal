import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  AbilityAware,
  AbilityPluginBinding,
} from '@ohos/flutter_ohos';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileUri } from '@kit.CoreFileKit';

/** GalPlugin - 相册保存核心，权限方法暂未实现 */
export default class GalPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private applicationContext: Context | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return "GalPlugin";
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
  }

  onDetachedFromAbility(): void {
    this.abilityBinding = null;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "gal");
    this.channel.setMethodCallHandler(this);
    this.applicationContext = binding.getApplicationContext();
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.applicationContext = null;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case "getPlatformVersion":
        result.success("OpenHarmony ^ ^ ");
        return;
      case "putImage":
        await this.handlePutImage(call, result);
        return;
      case "putVideo":
        await this.handlePutVideo(call, result);
        return;
      case "putImageBytes":
        await this.handlePutImageBytes(call, result);
        return;
      case "open":
        result.notImplemented();
        return;
      case "hasAccess":
      case "requestAccess":
        result.success(true);
        return;
      default:
        result.notImplemented();
    }
  }

  private async handlePutImage(call: MethodCall, result: MethodResult): Promise<void> {
    const path = call.args.get("path") as string;
    const album = call.args.get("album") as string | undefined;
    if (!path) {
      result.error("INVALID_ARGUMENT", "path is required", null);
      return;
    }
    try {
      await this.saveToGallery(path, photoAccessHelper.PhotoType.IMAGE, album);
      result.success(null);
    } catch (err) {
      result.error("SAVE_FAILED", String((err as Error).message), null);
    }
  }

  private async handlePutVideo(call: MethodCall, result: MethodResult): Promise<void> {
    const path = call.args.get("path") as string;
    const album = call.args.get("album") as string | undefined;
    if (!path) {
      result.error("INVALID_ARGUMENT", "path is required", null);
      return;
    }
    try {
      await this.saveToGallery(path, photoAccessHelper.PhotoType.VIDEO, album);
      result.success(null);
    } catch (err) {
      result.error("SAVE_FAILED", String((err as Error).message), null);
    }
  }

  private async handlePutImageBytes(call: MethodCall, result: MethodResult): Promise<void> {
    const bytes = call.args.get("bytes") as Uint8Array;
    const album = call.args.get("album") as string | undefined;
    const name = call.args.get("name") as string;
    if (!bytes || bytes.length === 0) {
      result.error("INVALID_ARGUMENT", "bytes is required", null);
      return;
    }
    if (!this.applicationContext) {
      result.error("UNAVAILABLE", "applicationContext is null", null);
      return;
    }
    try {
      const cachePath = await this.writeImageBytesToCache(bytes);
      await this.saveToGallery(cachePath, photoAccessHelper.PhotoType.IMAGE, name);
      result.success(null);
    } catch (err) {
      result.error("SAVE_FAILED", String((err as Error).message), null);
    }
  }

  /** 将文件/缓存路径保存到相册（图片或视频） */
  private async saveToGallery(
    path: string,
    photoType: photoAccessHelper.PhotoType,
    title?: string
  ): Promise<void> {
    const ctx = this.abilityBinding?.getAbility()?.context;
    if (!ctx) {
      throw new Error("ability context is null");
    }
    if (!fs.accessSync(path)) {
      throw new Error(`file not exist: ${path}`);
    }
    const ext = this.getFileExtension(path);
    const fileNameExtension = ext.length > 0 ? ext : (photoType === photoAccessHelper.PhotoType.IMAGE ? "jpg" : "mp4");
    const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(ctx);
    const srcFileUris: string[] = [fileUri.getUriFromPath(path)];
    const photoCreationConfigs: photoAccessHelper.PhotoCreationConfig[] = [{
      title: title ?? String(Date.now()),
      fileNameExtension,
      photoType,
      subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
    }];
    const desFileUris: string[] = await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
    const srcFile = await fs.open(path, fs.OpenMode.READ_ONLY);
    const targetFile = await fs.open(desFileUris[0], fs.OpenMode.READ_WRITE);
    fs.copyFileSync(srcFile.fd, targetFile.fd);
    fs.closeSync(srcFile);
    fs.closeSync(targetFile);
  }

  /** 将图片字节写入缓存并压缩为 jpg，返回缓存路径 */
  private async writeImageBytesToCache(bmp: Uint8Array): Promise<string> {
    const cacheDir = this.applicationContext?.cacheDir;
    if (!cacheDir) {
      throw new Error("cacheDir is null");
    }
    const filePath = `${cacheDir}/gal_image_source.jpg`;
    const outFile = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    await fs.write(outFile.fd, bmp.buffer);
    const imageSource = image.createImageSource(outFile.fd);
    const imagePacker = image.createImagePacker();
    const imageBuffer = await imagePacker.packing(imageSource, { format: "image/jpeg", quality: 100 });
    fs.closeSync(outFile.fd);
    const outImage = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    await fs.write(outImage.fd, imageBuffer);
    fs.closeSync(outImage.fd);
    return filePath;
  }

  private getFileExtension(path: string): string {
    const parts = path.split('.');
    return parts.length >= 2 ? parts[parts.length - 1] : '';
  }
}
