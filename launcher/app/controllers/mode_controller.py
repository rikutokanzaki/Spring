from app.controllers import docker_manager, session_manager
import threading
import time
import logging

logger = logging.getLogger(__name__)

class ModeController:
    def __init__(self):
        self.current_mode = "sakura"
        self.modes = ["sakura", "yozakura", "tsubomi"]
        self.rotate_interval = 1020
        self._start_rotation_timer()

    def _start_rotation_timer(self):
        def rotate():
            while True:
                time.sleep(self.rotate_interval)
                self._rotate_mode()

        thread = threading.Thread(target=rotate, daemon=True)
        thread.start()

    def _rotate_mode(self):
        current_idx = self.modes.index(self.current_mode)
        next_idx = (current_idx + 1) % len(self.modes)
        self.current_mode = self.modes[next_idx]
        logger.info(f"[mode-rotate] -> {self.current_mode}")
        self._apply_mode_change()

    def _apply_mode_change(self):
        if self.current_mode == "sakura":
            self._trigger_container("heralding", persist=True)
            self._stop_container("wordpot")
            self._stop_container("h0neytr4p")
            self._stop_container("cowrie")
        elif self.current_mode == "yozakura":
            self._trigger_container("heralding", persist=True)
            self._trigger_container("wordpot", persist=True)
            self._trigger_container("h0neytr4p", persist=True)
            self._trigger_container("cowrie", persist=True)
        elif self.current_mode == "tsubomi":
            self._stop_container("wordpot")
            self._stop_container("heralding")
            self._trigger_container("h0neytr4p", persist=True)
            self._trigger_container("cowrie", persist=True)

    def _trigger_container(self, service_name: str, persist: bool = True):
        try:
            session_manager.update_session(service_name, persist=persist)

            service = session_manager._services.get(service_name)
            if service:
                with service.stop_lock:
                    if not docker_manager.is_service_running(service_name):
                        docker_manager.start_services([service_name])
                        logger.info(f"Started {service_name}")
            else:
                logger.warning(f"Service {service_name} not found in session_manager")
        except Exception as e:
            logger.exception(f"Error triggering {service_name}: {e}")

    def _stop_container(self, service_name: str):
        try:
            session_manager.ensure_session(service_name, persist=False)

            service = session_manager._services.get(service_name)
            if service:
                with service.stop_lock:
                    if docker_manager.is_service_running(service_name):
                        docker_manager.stop_services([service_name])
                        logger.info(f"Stopped {service_name}")
            else:
                logger.warning(f"Service {service_name} not found in session_manager")
        except Exception as e:
            logger.exception(f"Error stopping {service_name}: {e}")

    def get_current_mode(self) -> str:
        return self.current_mode
