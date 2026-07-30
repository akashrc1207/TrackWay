from django.apps import AppConfig


class ApiConfig(AppConfig):
    name = "api"

    def ready(self):
        try:
            from .services.eta_service import _load_v5_lstm_model, _load_model

            _load_v5_lstm_model()
            _load_model()
        except Exception:
            pass
