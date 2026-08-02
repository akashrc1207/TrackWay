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
        pred_eta_fwd, engine_fwd = predict_eta_with_ml(
            current_lat=12.0369964,
            current_lng=75.3600476,
            current_speed_kmh=35.0,
            target_lat=12.2746351,
            target_lng=75.3637389,
            target_stop_order=38,
            direction_flag=0
        )
        self.assertIsNotNone(pred_eta_fwd)
        self.assertGreater(pred_eta_fwd, 30.0)

    def test_return_journey_eta_prediction(self):
        # Current location at Cherupuzha, target at Thaliparamba (stop order 1) - Return
        pred_eta_ret, engine_ret = predict_eta_with_ml(
            current_lat=12.2746351,
            current_lng=75.3637389,
            current_speed_kmh=35.0,
            target_lat=12.0369964,
            target_lng=75.3600476,
            target_stop_order=1,
            direction_flag=1
        )
        self.assertIsNotNone(pred_eta_ret)
        self.assertGreater(pred_eta_ret, 30.0)

    def test_calculate_eta_service(self):
        res = calculate_eta(
            current_lat=12.0369964,
            current_lng=75.3600476,
            current_speed_kmh=30.0,
            target_lat=12.1680284,
            target_lng=75.4628332, # Karuvanchal (midpoint stop)
            target_stop_order=17
        )
        self.assertIn("eta_minutes", res)
        self.assertTrue(res["is_ml"])
        self.assertTrue(any(name in res["prediction_engine"] for name in ["ExtraTrees", "Keras LSTM", "Physics"]))
        self.assertGreater(res["eta_minutes"], 0)


class BusETAApiTest(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.route = Route.objects.create(
            route_name="Thaliparamba - Cherupuzha",
            start_location="Thaliparamba",
            end_location="Cherupuzha",
            total_distance=45.0
        )
        self.bus = Bus.objects.create(
            bus_number="KL-59-A-1234",
            capacity=50,
            route=self.route,
            status="Active"
        )
        self.stop1 = BusStop.objects.create(
            stop_name="Thaliparamba",
            latitude=12.0369964,
            longitude=75.3600476,
            route=self.route,
            stop_order=1
        )
        self.stop2 = BusStop.objects.create(
            stop_name="Karuvanchal",
            latitude=12.1680284,
            longitude=75.4628332,
            route=self.route,
            stop_order=17
        )
        self.gps = GPSLog.objects.create(
            bus=self.bus,
            latitude=12.037135,
            longitude=75.360110,
            speed=25.5
        )

    def test_get_bus_eta_endpoint(self):
        url = reverse("bus-eta", kwargs={"bus_id": self.bus.id})
        response = self.client.get(url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertEqual(data["bus_number"], "KL-59-A-1234")
        self.assertEqual(len(data["stops_eta"]), 2)
        self.assertTrue(data["stops_eta"][0]["is_ml"])

    def test_metrics_summary_endpoint(self):
        url = reverse("metrics-summary")
        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertEqual(data["status"], "healthy")
        self.assertIn("telemetry", data)
        self.assertIn("gps_packets", data["telemetry"])
        self.assertIn("eta_engine", data["telemetry"])


class DynamicBusSelectionTest(TestCase):

    def setUp(self):
        from django.contrib.auth.models import User
        self.client = APIClient()
        self.route = Route.objects.create(
            route_name="Thaliparamba - Cherupuzha",
            start_location="Thaliparamba",
            end_location="Cherupuzha",
            total_distance=45.0
        )
        self.bus1 = Bus.objects.create(
            bus_name="Nayana",
            bus_number="KL-59-N-4005",
            capacity=50,
            route=self.route
        )
        self.bus2 = Bus.objects.create(
            bus_name="Holy Angel",
            bus_number="KL-59-M-6555",
            capacity=55,
            route=self.route
        )
        self.user1 = User.objects.create_user(username="driver1", password="password123")
        self.user2 = User.objects.create_user(username="driver2", password="password123")

    def test_available_buses_endpoint(self):
        url = reverse("available-buses")
        res = self.client.get(url)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.json()), 2)

    def test_bus_locking_and_release(self):
        self.client.force_authenticate(user=self.user1)

        # 1. Driver 1 starts journey on Bus 1
        start_url = reverse("start-journey")
        res = self.client.post(start_url, {"bus_id": self.bus1.id}, format="json")
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

        # 2. Available buses should now exclude Bus 1
        avail_url = reverse("available-buses")
        res_avail = self.client.get(avail_url)
        avail_ids = [b["id"] for b in res_avail.json()]
        self.assertNotIn(self.bus1.id, avail_ids)
        self.assertIn(self.bus2.id, avail_ids)

        # 3. Driver 2 attempts to lock Bus 1 (should fail with 400 Bad Request)
        client2 = APIClient()
        client2.force_authenticate(user=self.user2)
        res_dup = client2.post(start_url, {"bus_id": self.bus1.id}, format="json")
        self.assertEqual(res_dup.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("error", res_dup.json())

        # 4. Driver 1 stops journey -> releases Bus 1
        stop_url = reverse("stop-journey")
        res_stop = self.client.post(stop_url)
        self.assertEqual(res_stop.status_code, status.HTTP_200_OK)

        # 5. Bus 1 is now available again
        res_avail_after = self.client.get(avail_url)
        avail_ids_after = [b["id"] for b in res_avail_after.json()]
        self.assertIn(self.bus1.id, avail_ids_after)
