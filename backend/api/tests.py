from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework import status

from .models import Route, Bus, BusStop, GPSLog
from .services.eta_service import calculate_eta, predict_eta_with_ml, haversine_distance


class ETAServiceTest(TestCase):

    def test_haversine_distance(self):
        # Distance between Thaliparamba (12.0370, 75.3600) and Cherupuzha (12.2746, 75.3637)
        dist = haversine_distance(12.0369964, 75.3600476, 12.2746351, 75.3637389)
        self.assertGreater(dist, 20.0)
        self.assertLess(dist, 40.0)

    def test_ml_eta_prediction(self):
        # Current location at Thaliparamba, target at Cherupuzha (stop order 38) - Forward
        pred_eta_fwd = predict_eta_with_ml(
            current_lat=12.0369964,
            current_lng=75.3600476,
            current_speed_kmh=35.0,
            target_lat=12.2746351,
            target_lng=75.3637389,
            target_stop_order=38,
            direction_flag=0,
        )
        self.assertIsNotNone(pred_eta_fwd)
        self.assertGreater(pred_eta_fwd, 30.0)

    def test_return_journey_eta_prediction(self):
        # Current location at Cherupuzha, target at Thaliparamba (stop order 1) - Return
        pred_eta_ret = predict_eta_with_ml(
            current_lat=12.2746351,
            current_lng=75.3637389,
            current_speed_kmh=35.0,
            target_lat=12.0369964,
            target_lng=75.3600476,
            target_stop_order=1,
            direction_flag=1,
        )
        self.assertIsNotNone(pred_eta_ret)
        self.assertGreater(pred_eta_ret, 30.0)

    def test_calculate_eta_service(self):
        res = calculate_eta(
            current_lat=12.0369964,
            current_lng=75.3600476,
            current_speed_kmh=30.0,
            target_lat=12.1680284,
            target_lng=75.4628332,  # Karuvanchal (midpoint stop)
            target_stop_order=17,
        )
        self.assertIn("eta_minutes", res)
        self.assertTrue(res["is_ml"])
        self.assertIn("Keras LSTM", res["prediction_engine"])
        self.assertGreater(res["eta_minutes"], 0)


class BusETAApiTest(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.route = Route.objects.create(
            route_name="Thaliparamba - Cherupuzha",
            start_location="Thaliparamba",
            end_location="Cherupuzha",
            total_distance=45.0,
        )
        self.bus = Bus.objects.create(
            bus_number="KL-59-A-1234", capacity=50, route=self.route, status="Active"
        )
        self.stop1 = BusStop.objects.create(
            stop_name="Thaliparamba",
            latitude=12.0369964,
            longitude=75.3600476,
            route=self.route,
            stop_order=1,
        )
        self.stop2 = BusStop.objects.create(
            stop_name="Karuvanchal",
            latitude=12.1680284,
            longitude=75.4628332,
            route=self.route,
            stop_order=17,
        )
        self.gps = GPSLog.objects.create(
            bus=self.bus, latitude=12.037135, longitude=75.360110, speed=25.5
        )

    def test_get_bus_eta_endpoint(self):
        url = reverse("bus-eta", kwargs={"bus_id": self.bus.id})
        response = self.client.get(url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertEqual(data["bus_number"], "KL-59-A-1234")
        self.assertEqual(len(data["stops_eta"]), 2)
        self.assertTrue(data["stops_eta"][0]["is_ml"])
