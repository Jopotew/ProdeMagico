// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/prode"
import topbar from "../vendor/topbar"

// Hook: subscribes the browser to web push and reports back to LiveView
const PushSubscription = {
  mounted() {
    this.el.addEventListener("click", () => this.subscribe())
  },
  subscribe() {
    if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
      this.pushEvent("push_not_supported", {})
      return
    }
    const vapidKey = document
      .querySelector("meta[name='vapid-public-key']")
      ?.getAttribute("content")
    if (!vapidKey) {
      this.pushEvent("push_not_supported", {})
      return
    }
    Notification.requestPermission().then(permission => {
      if (permission !== "granted") {
        this.pushEvent("push_denied", {})
        return
      }
      navigator.serviceWorker.ready.then(reg => {
        reg.pushManager
          .subscribe({userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(vapidKey)})
          .then(sub => {
            const json = sub.toJSON()
            this.pushEvent("push_subscribed", {
              endpoint: json.endpoint,
              p256dh: json.keys?.p256dh,
              auth: json.keys?.auth,
            })
          })
          .catch(() => this.pushEvent("push_error", {}))
      })
    })
  }
}

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
  const rawData = atob(base64)
  return Uint8Array.from([...rawData].map(char => char.charCodeAt(0)))
}

// Scroll the fixture day heading for today into view on mount
const ScrollToToday = {
  mounted() {
    this.el.scrollIntoView({ behavior: "instant", block: "start" })
  }
}

// Fires "load_more" when the sentinel element scrolls into view
const InfiniteScroll = {
  mounted() {
    this.observer = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting) {
        this.pushEvent("load_more", {})
      }
    }, { rootMargin: "200px" })
    this.observer.observe(this.el)
  },
  destroyed() {
    this.observer?.disconnect()
  }
}

// Copy text to clipboard via phx:copy_to_clipboard event
window.addEventListener("phx:copy_to_clipboard", (e) => {
  navigator.clipboard?.writeText(e.detail.text).then(() => {}).catch(() => {})
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, PushSubscription, ScrollToToday, InfiniteScroll},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// Register service worker for PWA offline support
if ("serviceWorker" in navigator && process.env.NODE_ENV !== "development") {
  navigator.serviceWorker.register("/sw.js").catch(() => {});
}

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

