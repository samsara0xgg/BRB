export type Lang = "en" | "zh";

// A caption line: plain text, with *stars* around the words drawn in amber.
type Lines = string[];

type Copy = {
  introSub: string;
  setup: Lines;
  setupSub: string;
  arm: Lines;
  armSub: string;
  guard: Lines;
  guardSub: string;
  touch: Lines;
  touchSub: string;
  lift: Lines;
  liftSub: string;
  phone: Lines;
  phoneSub: string;
  putback: Lines;
  putbackSub: string;
  back: Lines;
  backSub: string;
  bentoTitle: string;
  bento: { title: string; sub: string }[];
  endTag: string;
  endLine: string;
  endCta: string;
  endFine: string;
  // The Mac's own words (the app's real strings).
  mac: {
    menuApp: string;
    menus: string[];
    clock: string;
    clockBack: string;
    ready: string;
    start: string;
    startSub: string;
    places: [string, string, string];
    hint: string;
    note: string;
    recent: string;
    recents: { title: string; sub: string; kind: "ok" | "alarm" }[];
    leave: string;
    cancels: string;
    touchId: string;
    dontTouch: string;
    guarded: string;
    walkBy: string;
    noteChip: string;
    footer: string;
    alarm: string;
    onCamera: string;
    recording: string;
    sirenOff: string;
    sirenOffSub: string;
    welcome: string;
    welcomeSub: string;
    photos: string;
    sirenFor: string;
  };
  phoneUi: {
    time: string;
    date: string;
    pickedUp: string;
    sirenOn: string;
    stopSiren: string;
    open: string;
    alarmCaps: string;
    headline: string;
    metaFmt: string; // {e} is the time since it started
    live: string;
    zoom: string;
    statusTitle: string;
    statusSub: string;
    ev: { touch: string; lift: string; siren: string; push: string; photo: string };
    savePhotos: string;
    evidence: string;
    disarm: string;
    macName: string;
    putBack: string;
    putBackSub: string;
  };
};

const en: Copy = {
  introSub: "",
  setup: ["Stepping away?"],
  setupSub: "Leave your Mac. BRB keeps watch.",
  arm: ["One click."],
  armSub: "Every screen frosts over and asks people not to touch.",
  guard: ["Walk past?", "*Nothing happens.*"],
  guardSub: "Passing by is never recorded.",
  touch: ["Touch it,", "and it *raises*| *the alarm.*"],
  touchSub: "Red screen. Locked. Recording.",
  lift: ["Take it?", "The siren *won’t stop.*"],
  liftSub: "Lift, tilt, shut the lid or unplug it.",
  phone: ["See it live", "on your *iPhone.*"],
  phoneSub: "Faces in the background stay blurred.",
  putback: ["Put it back.", "*It goes quiet.*"],
  putbackSub: "The siren stops by itself.",
  back: ["Back?", "*One touch*| and it’s yours."],
  backSub: "Touch ID ends the watch.",
  bentoTitle: "All of this is *free.*",
  bento: [
    { title: "Frosted screen", sub: "Asks people not to touch" },
    { title: "Feels every move", sub: "Lift, lid, keys, charger" },
    { title: "10 s before", sub: "Saved on video" },
    { title: "Faces blurred", sub: "Only the one at your Mac" },
    { title: "Live on iPhone", sub: "Alerts, photos, live view" },
    { title: "No subscription", sub: "Free to download" },
  ],
  endTag: "Be right back.",
  endLine: "Your Mac keeps watch until you’re back.",
  endCta: "Free for Mac",
  endFine: "Apple silicon · macOS 14 or later",
  mac: {
    menuApp: "Notes",
    menus: ["File", "Edit", "Format", "View", "Window", "Help"],
    clock: "Thu 3:34 PM",
    clockBack: "Thu 3:44 PM",
    ready: "Ready",
    start: "Start guarding",
    startSub: "Starts in 5 s · leave it lying still",
    places: ["Library", "Café", "On the go"],
    hint: "Busy table: bumps are ignored, carrying it is not",
    note: "Back in 10 min",
    recent: "Recent",
    recents: [
      { title: "Nobody touched it", sub: "Today 12:36 PM · Away 23 min", kind: "ok" },
      { title: "Someone touched the trackpad", sub: "Yesterday 4:12 PM · Disarmed with Touch ID", kind: "alarm" },
      { title: "Ignored 2 bumps", sub: "Oct 11 · Away 51 min", kind: "ok" },
    ],
    leave: "Leave it lying still and walk away",
    cancels: "cancels",
    touchId: "or rest a finger on Touch ID",
    dontTouch: "Please don’t touch",
    guarded: "This Mac is guarded. Touching it sounds the alarm.",
    walkBy: "Walking by isn’t recorded. Touching it is.",
    noteChip: "“Back in 10 min” · 3:34 PM",
    footer: "请勿触碰 · 路过不会被录下",
    alarm: "Alarm raised",
    onCamera: "You’re on camera. The owner has been notified.",
    recording: "Recording",
    sirenOff: "Siren off",
    sirenOffSub: "It’s back in place. Still on camera.",
    welcome: "Welcome back",
    welcomeSub: "At 3:41 PM, someone picked up your Mac",
    photos: "3 photos sent to your phone",
    sirenFor: "The siren sounded for 6 s",
  },
  phoneUi: {
    time: "3:41",
    date: "Thursday, October 16",
    pickedUp: "Picked up",
    sirenOn: "Siren on",
    stopSiren: "Stop siren",
    open: "Open",
    alarmCaps: "ALARM",
    headline: "Your MacBook was picked up",
    metaFmt: "3:41 PM · {e} ago · MacBook Pro",
    live: "LIVE",
    zoom: "Double-tap to zoom",
    statusTitle: "Siren on",
    statusSub: "Stops when it’s put back",
    ev: { touch: "Trackpad touched", lift: "Picked up", siren: "Siren on", push: "Sent to your phone", photo: "Photo taken" },
    savePhotos: "Save photos",
    evidence: "Evidence",
    disarm: "Disarm",
    macName: "MacBook Pro",
    putBack: "Put back, siren off",
    putBackSub: "Still locked and filming.",
  },
};

const zh: Copy = {
  introSub: "马上回来",
  setup: ["要离开一下？"],
  setupSub: "电脑留在桌上，BRB 帮你看着。",
  arm: ["一键开启。"],
  armSub: "每块屏幕都变成磨砂玻璃，提醒别人别碰。",
  guard: ["有人路过？", "*什么都不会发生。*"],
  guardSub: "路过不会被录下。",
  touch: ["有人碰它，", "*立刻报警。*"],
  touchSub: "屏幕变红 · 锁屏 · 录像",
  lift: ["想拿走？", "警笛*响个不停。*"],
  liftSub: "拿起、倾斜、合盖、拔电源，都会报警。",
  phone: ["在 *iPhone* 上", "实时看到。"],
  phoneSub: "背景里的路人，自动打码。",
  putback: ["放回原处，", "*警笛就停。*"],
  putbackSub: "不用你动手。",
  back: ["回来了？", "*指纹一按*，|一切如常。"],
  backSub: "触控 ID 一按就解除。",
  bentoTitle: "这些，全部*免费*。",
  bento: [
    { title: "磨砂屏幕", sub: "提醒别人别碰" },
    { title: "动一下都知道", sub: "拿起 · 合盖 · 按键 · 拔电" },
    { title: "碰之前 10 秒", sub: "也录下来" },
    { title: "路人自动打码", sub: "只拍清碰电脑的人" },
    { title: "iPhone 实时看", sub: "提醒 · 照片 · 实时画面" },
    { title: "不用订阅", sub: "免费下载" },
  ],
  endTag: "马上回来。",
  endLine: "BRB 替你看着，等你回来。",
  endCta: "Mac 版免费下载",
  endFine: "Apple 芯片 · macOS 14 或更新",
  mac: {
    menuApp: "备忘录",
    menus: ["文件", "编辑", "格式", "显示", "窗口", "帮助"],
    clock: "周四 下午3:34",
    clockBack: "周四 下午3:44",
    ready: "就绪",
    start: "开始警戒",
    startSub: "5 秒后开始 · 放着别动",
    places: ["图书馆", "咖啡馆", "路上"],
    hint: "热闹的桌子：轻碰不算，拿走才算",
    note: "10 分钟回来",
    recent: "最近",
    recents: [
      { title: "没人碰过", sub: "今天 12:36 · 离开 23 分钟", kind: "ok" },
      { title: "有人碰了触控板", sub: "昨天 16:12 · 用指纹解除", kind: "alarm" },
      { title: "忽略了 2 次轻碰", sub: "10月11日 · 离开 51 分钟", kind: "ok" },
    ],
    leave: "放着别动，离开吧",
    cancels: "取消",
    touchId: "或把手指放在触控 ID 上",
    dontTouch: "请勿触碰",
    guarded: "这台电脑正在警戒，碰它会报警",
    walkBy: "路过不会被录下，碰它才会录像",
    noteChip: "“10 分钟回来” · 15:34",
    footer: "PLEASE DO NOT TOUCH · PASSING BY IS NOT RECORDED",
    alarm: "已报警",
    onCamera: "画面已录下，机主已收到通知",
    recording: "正在录像",
    sirenOff: "警笛已停",
    sirenOffSub: "已放回原处，仍在录像",
    welcome: "欢迎回来",
    welcomeSub: "15:41 有人拿起了电脑",
    photos: "3 张照片已发到手机",
    sirenFor: "警笛响了 6 秒",
  },
  phoneUi: {
    time: "15:41",
    date: "10月16日 星期四",
    pickedUp: "被拿起",
    sirenOn: "鸣笛中",
    stopSiren: "停止鸣笛",
    open: "打开",
    alarmCaps: "报警",
    headline: "你的 MacBook 被拿起了",
    metaFmt: "15:41 触发 · 已过去 {e} · MacBook Pro",
    live: "直播",
    zoom: "双击放大",
    statusTitle: "鸣笛中",
    statusSub: "放回原位就会停",
    ev: { touch: "碰到触控板", lift: "被拿起", siren: "开始鸣笛", push: "已推送到手机", photo: "拍了一张照片" },
    savePhotos: "保存照片",
    evidence: "证据包",
    disarm: "解除警报",
    macName: "MacBook Pro",
    putBack: "已放回，已停响",
    putBackSub: "仍锁屏，继续录像。",
  },
};

export const COPY: Record<Lang, Copy> = { en, zh };
export type { Copy };
