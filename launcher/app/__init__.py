from flask import Flask
from werkzeug.middleware.proxy_fix import ProxyFix
from app.routes import bp
from app.controllers.mode_controller import ModeController
import logging

logging.basicConfig(
  level=logging.WARNING,
  format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
)

def create_app():
  app = Flask(__name__)
  app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1)

  mode_controller = ModeController()
  app.config['mode_controller'] = mode_controller

  app.register_blueprint(bp)

  return app
