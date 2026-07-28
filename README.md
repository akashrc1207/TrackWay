# TrackWay 🚌⚡
> **AI-Powered Real-Time Bus & ETA Tracking System**

![TrackWay Banner](https://img.shields.io/badge/TrackWay-Vibrant%20Commuter-059669?style=for-the-badge&logo=flutter)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter)
![Django](https://img.shields.io/badge/Django_REST-4.x-092E20?style=for-the-badge&logo=django)
![Python](https://img.shields.io/badge/Python-3.10+-3776AB?style=for-the-badge&logo=python)
![Machine Learning](https://img.shields.io/badge/ML-ETA_Predictor-FF6F00?style=for-the-badge&logo=scikitlearn)

**TrackWay** is an intelligent, real-time public transit tracking system built with a **Flutter** mobile application and a **Django REST Framework** backend. It features live driver GPS telemetry, machine learning-driven ETA calculation, and a **Vibrant Modern Commuter** user interface.

---

## ✨ Features

- 📍 **Real-Time GPS Telemetry**: Drivers stream live location & speed updates every 4 seconds directly from the **Driver Control Hub**.
- 🤖 **AI Machine Learning ETA Predictor**: Intelligent ETA algorithm combining Haversine spatial calculation with trained ML models (`joblib` / `scikit-learn` / `onnx`).
- 🎨 **Vibrant Modern Commuter UI**: Designed with a fresh Mint & Emerald theme (`#059669`), rounded floating route cards, speed gauges, and glassmorphic map sheets.
- 🚏 **Station Sequence & Stop Navigation**: View upcoming stops, route distances, passenger capacities, and estimated arrival counters.
- 🔐 **Dual Mode Portals**: Seamless separation between Passenger Commuter Mode and Driver Duty Login.

---

## 🛠️ Technology Stack

| Layer | Technology |
| :--- | :--- |
| **Frontend Mobile App** | Flutter (Dart), Flutter Map, Geolocator, SharedPreferences |
| **Backend REST API** | Python, Django, Django REST Framework, SQLite |
| **AI / Machine Learning** | Joblib, Scikit-Learn / PyTorch, NumPy |
| **Mapping & GIS** | OpenStreetMap, LatLong2 |

---

## 📂 Project Structure

```text
TrackWay/
├── backend/                  # Django REST API Backend
│   ├── api/
│   │   ├── models.py         # Route, Bus, BusStop, GPSLog, Journey models
│   │   ├── views.py          # API endpoints for GPS update & ETA queries
│   │   ├── serializers.py    # Serializer definitions
│   │   ├── services/
│   │   │   └── eta_service.py# AI & Haversine ETA prediction engine
│   │   └── ml_models/        # Exported Colab ML models (.pkl / .joblib)
│   ├── manage.py
│   └── trackway/             # Project settings & URLs
│
└── trackway_app/             # Flutter Mobile Application
    └── lib/
        ├── config/
        │   ├── app_theme.dart# Concept 1 Mint & Emerald theme tokens
        │   └── api_constants.dart
        ├── models/           # Data models (Bus, GPS, RouteDetails)
        ├── screens/
        │   ├── home/         # Passenger HomeScreen & RouteDetailsScreen
        │   ├── tracking/     # Live TrackingScreen with map overlay
        │   ├── driver/       # DriverDashboard with broadcast switch
        │   └── login/        # Mode selection & Driver Login
        └── services/         # API Service & HTTP client
```

---

## 🚀 Getting Started

### 1. Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.0+)
- [Python 3.10+](https://www.python.org/downloads/)
- [Git](https://git-scm.com/)

---

### 2. Backend Setup (Django API)

1. Open terminal and navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Create & activate a virtual environment:
   ```bash
   # Windows (PowerShell)
   python -m venv venv
   .\venv\Scripts\activate
   ```

3. Install dependencies:
   ```bash
   pip install django djangorestframework django-cors-headers joblib scikit-learn numpy
   ```

4. Run database migrations:
   ```bash
   python manage.py migrate
   ```

5. Start the backend server:
   ```bash
   python manage.py runserver 0.0.0.0:8000
   ```
   *The Django REST API will run at `http://localhost:8000/api/`*

---

### 3. Mobile App Setup (Flutter)

1. Open a new terminal and navigate to the app folder:
   ```bash
   cd trackway_app
   ```

2. Get Flutter packages:
   ```bash
   flutter pub get
   ```

3. Launch on an Android Emulator / Connected Device:
   ```bash
   flutter run
   ```

---

## 🧠 ML Model Integration (Google Colab to Django)

1. Export your trained model in Colab using `joblib`:
   ```python
   import joblib
   joblib.dump(model, 'eta_model.pkl')
   ```
2. Place `eta_model.pkl` in `backend/api/ml_models/`.
3. `eta_service.py` will automatically detect and load your ML model on server startup.

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
