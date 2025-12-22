from mode.mode_manager import ModeManager
import logging
import time
import threading
import requests

logging.basicConfig(
  level=logging.INFO,
  format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
)

logger = logging.getLogger(__name__)

MODES = ["sakura", "yozakura", "tsubomi"]
ROTATE_INTERVAL = 60
LAUNCHER_BASE_URL = "http://launcher:5000"

mode_manager = ModeManager()

def _post_to_launcher(path: str) -> bool:
  try:
    url = f"{LAUNCHER_BASE_URL}/{path}"
    response = requests.post(url, timeout=5)

    if response.status_code == 200:
      logger.info("[launcher] POST /%s status=%s", path, response.status_code)
      return True
    else:
      logger.error("[launcher] POST /%s failed with status=%s", path, response.status_code)
      return False

  except Exception:
    logger.exception("[launcher] POST /%s failed", path)
    return False

def handle_mode_change(new_mode: str) -> None:
  logger.info("[mode-change] -> %s", new_mode)

  if new_mode == "sakura":
    _post_to_launcher("trigger-infty/heralding")
    _post_to_launcher("stop/wordpot")
    _post_to_launcher("stop/h0neytr4p")
    _post_to_launcher("stop/cowrie")

  elif new_mode == "yozakura":
    _post_to_launcher("trigger-infty/heralding")
    _post_to_launcher("trigger-infty/wordpot")
    _post_to_launcher("trigger-infty/h0neytr4p")
    _post_to_launcher("trigger-infty/cowrie")

  elif new_mode == "tsubomi":
    _post_to_launcher("stop/wordpot")
    _post_to_launcher("stop/h0neytr4p")
    _post_to_launcher("stop/heralding")
    _post_to_launcher("trigger-infty/cowrie")

def rotate_mode() -> None:
  current_idx = MODES.index(mode_manager.get_mode())
  next_idx = (current_idx + 1) % len(MODES)
  new_mode = MODES[next_idx]

  mode_manager.set_mode(new_mode)
  logger.info("[mode-rotate] -> %s", new_mode)

  handle_mode_change(new_mode)

def start_worker() -> None:
  initial_mode = mode_manager.get_mode()
  logger.info("[mode-init] mode=%s", initial_mode)

  handle_mode_change(initial_mode)

  while True:
    try:
      time.sleep(ROTATE_INTERVAL)
      rotate_mode()

    except Exception:
      logger.exception("Error in mode rotation loop")
      time.sleep(10)

def start_worker_thread() -> threading.Thread:
  worker_thread = threading.Thread(target=start_worker, daemon=True)
  worker_thread.start()
  logger.info("Worker thread started")
  return worker_thread

if __name__ == "__main__":
  start_worker()
