import { describe, expect, test, vi } from "vitest";
import { KeepAwake, type VideoLike, type WakeLockSentinelLike } from "../src/phone/keep-awake";

function fakeSentinel() {
  let onRelease = (): void => undefined;
  const sentinel = {
    released: false,
    release: vi.fn(() => {
      sentinel.released = true;
      onRelease();
      return Promise.resolve();
    }),
    addEventListener: (_type: "release", listener: () => void) => {
      onRelease = listener;
    },
    /** The browser dropped the lock, e.g. because the page was hidden. */
    drop: () => {
      onRelease();
    },
  };
  return sentinel;
}

function fakeVideo(playResult: () => Promise<void> = () => Promise.resolve()) {
  const video = {
    paused: true,
    play: vi.fn(() =>
      playResult().then(() => {
        video.paused = false;
      }),
    ),
    pause: vi.fn(() => {
      video.paused = true;
    }),
  };
  return video;
}

function setup(options: { lock?: () => Promise<WakeLockSentinelLike>; video?: VideoLike } = {}) {
  let visible = true;
  let onVisibility = (): void => undefined;
  const video = options.video ?? fakeVideo();
  const createVideo = vi.fn(() => video);
  const request = options.lock ? vi.fn(options.lock) : undefined;
  const keepAwake = new KeepAwake({
    ...(request ? { wakeLock: { request } } : {}),
    createVideo,
    isVisible: () => visible,
    onVisibilityChange: (listener) => {
      onVisibility = listener;
    },
  });
  const setVisible = (value: boolean): void => {
    visible = value;
    onVisibility();
  };
  return { keepAwake, request, createVideo, video, setVisible };
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("KeepAwake with the Wake Lock API", () => {
  test("holds the lock only while connected", async () => {
    const sentinel = fakeSentinel();
    const { keepAwake, request, createVideo } = setup({ lock: () => Promise.resolve(sentinel) });

    keepAwake.set(true);
    await flush();
    expect(request).toHaveBeenCalledWith("screen");

    keepAwake.set(false);
    expect(sentinel.release).toHaveBeenCalled();
    expect(createVideo).not.toHaveBeenCalled();
  });

  test("takes the lock again when the page comes back after the browser dropped it", async () => {
    const sentinel = fakeSentinel();
    const { keepAwake, request, setVisible } = setup({ lock: () => Promise.resolve(sentinel) });
    keepAwake.set(true);
    await flush();

    sentinel.drop();
    setVisible(false);
    expect(request).toHaveBeenCalledTimes(1);
    setVisible(true);
    await flush();
    expect(request).toHaveBeenCalledTimes(2);
  });

  test("releases a lock that arrives after the connection dropped", async () => {
    const sentinel = fakeSentinel();
    const { keepAwake } = setup({ lock: () => Promise.resolve(sentinel) });

    keepAwake.set(true);
    keepAwake.set(false);
    await flush();
    expect(sentinel.released).toBe(true);
  });

  test("falls back to the video when the lock is refused", async () => {
    const { keepAwake, video } = setup({ lock: () => Promise.reject(new Error("NotAllowed")) });

    keepAwake.set(true);
    await flush();
    expect(video.paused).toBe(false);
  });
});

describe("KeepAwake with the video fallback", () => {
  test("plays the video while connected and pauses it when disconnected", async () => {
    const { keepAwake, video, createVideo } = setup();

    keepAwake.set(false);
    expect(createVideo).not.toHaveBeenCalled();

    keepAwake.set(true);
    await flush();
    expect(video.paused).toBe(false);

    keepAwake.set(false);
    expect(video.paused).toBe(true);
  });

  test("tries again on a tap when the browser blocked playback", async () => {
    let blocked = true;
    const video = fakeVideo(() =>
      blocked ? Promise.reject(new Error("NotAllowed")) : Promise.resolve(),
    );
    const { keepAwake } = setup({ video });

    keepAwake.set(true);
    await flush();
    expect(video.paused).toBe(true);

    blocked = false;
    keepAwake.retry();
    await flush();
    expect(video.paused).toBe(false);
  });

  test("a tap while disconnected doesn't start the video", () => {
    const { keepAwake, createVideo } = setup();
    keepAwake.retry();
    expect(createVideo).not.toHaveBeenCalled();
  });
});
