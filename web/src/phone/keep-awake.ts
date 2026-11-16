// Keeps the phone screen on while it's connected to the Mac.
//
// The Wake Lock API only exists on secure pages (HTTPS, or localhost over USB). Over Wi-Fi the
// page is plain HTTP, so we play a muted, looping, invisible video instead. Chrome keeps the
// screen on for a playing video that covers at least 20% of the viewport and is mostly on
// screen. Its check uses position and size, not opacity, so the video can fill the screen at
// opacity 0.

export interface WakeLockSentinelLike {
  release(): Promise<void>;
  addEventListener(type: "release", listener: () => void): void;
}

export interface WakeLockLike {
  request(type: "screen"): Promise<WakeLockSentinelLike>;
}

export interface VideoLike {
  readonly paused: boolean;
  play(): Promise<void>;
  pause(): void;
}

export interface KeepAwakeDeps {
  /** `navigator.wakeLock`, if the page may use it. */
  wakeLock?: WakeLockLike;
  /** Makes the fallback video; called once, the first time it's needed. */
  createVideo: () => VideoLike;
  isVisible: () => boolean;
  onVisibilityChange: (listener: () => void) => void;
}

export class KeepAwake {
  private wanted = false;
  private sentinel: WakeLockSentinelLike | null = null;
  private requesting = false;
  private useVideo: boolean;
  private video: VideoLike | null = null;

  constructor(private readonly deps: KeepAwakeDeps) {
    this.useVideo = !deps.wakeLock;
    // Browsers drop the wake lock and pause background video when the page is hidden.
    deps.onVisibilityChange(() => {
      if (deps.isVisible()) this.apply();
    });
  }

  /** Keep the screen on, or let it turn off again. */
  set(on: boolean): void {
    if (on === this.wanted) return;
    this.wanted = on;
    this.apply();
  }

  /**
   * Call from a user tap. Without one, the browser may refuse to start the video (for example
   * in battery saver).
   */
  retry(): void {
    this.apply();
  }

  private apply(): void {
    if (this.useVideo) this.applyVideo();
    else this.applyLock();
  }

  private applyLock(): void {
    const { wakeLock } = this.deps;
    if (!wakeLock) return;
    if (!this.wanted) {
      const sentinel = this.sentinel;
      this.sentinel = null;
      void sentinel?.release().catch(() => undefined);
      return;
    }
    if (this.sentinel || this.requesting || !this.deps.isVisible()) return;
    this.requesting = true;
    wakeLock.request("screen").then(
      (sentinel) => {
        this.requesting = false;
        sentinel.addEventListener("release", () => {
          if (this.sentinel === sentinel) this.sentinel = null;
        });
        this.sentinel = sentinel;
        // Disconnected while the request was in flight.
        if (!this.wanted) this.applyLock();
      },
      () => {
        this.requesting = false;
        // Blocked, e.g. by a permissions policy: the video works without one.
        this.useVideo = true;
        this.applyVideo();
      },
    );
  }

  private applyVideo(): void {
    if (!this.wanted) {
      this.video?.pause();
      return;
    }
    this.video ??= this.deps.createVideo();
    if (this.video.paused) void this.video.play().catch(() => undefined);
  }
}

/** The keep-awake video: muted, looping, invisible, filling the screen, ignoring taps. */
export function createKeepAwakeVideo(doc: Document, src: string): HTMLVideoElement {
  const video = doc.createElement("video");
  video.className = "keep-awake";
  video.muted = true;
  video.loop = true;
  video.playsInline = true;
  // iOS checks the attributes, not just the properties, before it plays inline without a tap.
  video.setAttribute("muted", "");
  video.setAttribute("playsinline", "");
  video.preload = "auto";
  video.setAttribute("aria-hidden", "true");
  video.src = src;
  doc.body.append(video);
  return video;
}
