import logging
import threading

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
