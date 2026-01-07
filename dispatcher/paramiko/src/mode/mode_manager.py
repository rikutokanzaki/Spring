import logging
import threading
import time
import requests

logger = logging.getLogger(__name__)

class ModeManager:
  _instance = None
  _lock = threading.Lock()

  def __new__(cls):
    if cls._instance is None:
      with cls._lock:
        if cls._instance is None:
          cls._instance = super().__new__(cls)
          cls._instance._initialized = False
    return cls._instance

  def __init__(self):
    if self._initialized:
      return

    self._initialized = True
    self._mode_lock = threading.Lock()
    self._current_mode = "sakura"
    logger.info("ModeManager initialized with mode: %s", self._current_mode)

    self._start_sync_thread()

  def _fetch_current_mode(self) -> str:
    try:
      response = requests.get("http://launcher:5000/current-mode", timeout=2)
      if response.status_code == 200:
        mode = response.text.strip()
        return mode
      else:
        logger.warning("Failed to fetch mode from launcher: HTTP %s", response.status_code)
    except requests.exceptions.RequestException as e:
      logger.debug("Mode fetch error (will retry): %s", e)
    except Exception as e:
      logger.exception("Unexpected error fetching mode: %s", e)
    return None

  def _sync_mode(self):
    while True:
      try:
        time.sleep(10)
        new_mode = self._fetch_current_mode()
        if new_mode:
          with self._mode_lock:
            if self._current_mode != new_mode:
              old_mode = self._current_mode
              self._current_mode = new_mode
              logger.info("[mode-sync] %s -> %s", old_mode, new_mode)
      except Exception as e:
        logger.exception("Error in mode sync thread: %s", e)

  def _start_sync_thread(self):
    sync_thread = threading.Thread(target=self._sync_mode, daemon=True)
    sync_thread.start()

    init_thread = threading.Thread(target=self._initial_fetch, daemon=True)
    init_thread.start()

  def _initial_fetch(self):
    time.sleep(1)
    initial_mode = self._fetch_current_mode()
    if initial_mode:
      with self._mode_lock:
        self._current_mode = initial_mode
        logger.info("[mode-init] mode=%s", initial_mode)

  def get_mode(self) -> str:
    with self._mode_lock:
      return self._current_mode

  def set_mode(self, mode: str) -> None:
    valid_modes = ["sakura", "yozakura", "tsubomi"]
    if mode not in valid_modes:
      logger.error("Invalid mode: %s. Must be one of %s", mode, valid_modes)
      raise ValueError(f"Invalid mode: {mode}")

    with self._mode_lock:
      old_mode = self._current_mode
      self._current_mode = mode
      logger.info("Mode changed: %s -> %s", old_mode, mode)

  def is_sakura(self) -> bool:
    return self.get_mode() == "sakura"

  def is_yozakura(self) -> bool:
    return self.get_mode() == "yozakura"

  def is_tsubomi(self) -> bool:
    return self.get_mode() == "tsubomi"
