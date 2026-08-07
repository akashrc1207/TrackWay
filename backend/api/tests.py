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
        from django.contrib.auth.models import User
        from .models import Driver, Journey
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
        self.user = User.objects.create_user(username="driver_eta", password="pass")
        self.driver = Driver.objects.create(user=self.user, phone="+919999999999", assigned_bus=self.bus)
        self.journey = Journey.objects.create(bus=self.bus, driver=self.driver, is_active=True)
        self.gps = GPSLog.objects.create(
            bus=self.bus,
            journey=self.journey,
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
        self.stop1 = BusStop.objects.create(route=self.route, stop_order=1, stop_name="Thaliparamba", latitude=12.0369964, longitude=75.3600476)
        self.stop38 = BusStop.objects.create(route=self.route, stop_order=38, stop_name="Cherupuzha", latitude=12.2746351, longitude=75.3637389)

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
        res = self.client.post(start_url, {"bus_id": self.bus1.id, "latitude": 12.0369964, "longitude": 75.3600476}, format="json")
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

    def test_missing_bus_id_validation(self):
        self.client.force_authenticate(user=self.user1)
        start_url = reverse("start-journey")
        res = self.client.post(start_url, {}, format="json")
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(res.json().get("error"), "bus_id is required to start a journey.")

class ConcurrentMultiBusTest(TestCase):

    def setUp(self):
        from django.contrib.auth.models import User
        from api.models import Driver
        self.route = Route.objects.create(
            route_name="Thaliparamba - Cherupuzha",
            start_location="Thaliparamba",
            end_location="Cherupuzha",
            total_distance=45.1
        )
        self.stop1 = BusStop.objects.create(route=self.route, stop_order=1, stop_name="Thaliparamba", latitude=12.0369964, longitude=75.3600476)
        self.stop38 = BusStop.objects.create(route=self.route, stop_order=38, stop_name="Cherupuzha", latitude=12.2746351, longitude=75.3637389)

        self.busA = Bus.objects.create(bus_name="Nayana", bus_number="KL-59-N-4005", capacity=52, route=self.route)
        self.busB = Bus.objects.create(bus_name="Holy Angel", bus_number="KL-59-M-6555", capacity=48, route=self.route)
        self.busC = Bus.objects.create(bus_name="Big Show", bus_number="KL-59-Z-8499", capacity=55, route=self.route)

        self.user1 = User.objects.create_user(username="driver1", password="driver123")
        self.user2 = User.objects.create_user(username="driver2", password="driver123")
        self.user3 = User.objects.create_user(username="driver3", password="driver123")

        self.driver1 = Driver.objects.create(user=self.user1, phone="+919876543210")
        self.driver2 = Driver.objects.create(user=self.user2, phone="+919876543211")
        self.driver3 = Driver.objects.create(user=self.user3, phone="+919876543212")

    def test_three_buses_concurrent_operation(self):
        start_url = reverse("start-journey")
        update_gps_url = reverse("gps-update")

        client1 = APIClient()
        client1.force_authenticate(user=self.user1)
        res1 = client1.post(start_url, {"bus_id": self.busA.id, "latitude": 12.0369964, "longitude": 75.3600476}, format="json")
        self.assertEqual(res1.status_code, status.HTTP_201_CREATED)

        client2 = APIClient()
        client2.force_authenticate(user=self.user2)
        res2 = client2.post(start_url, {"bus_id": self.busB.id, "latitude": 12.0369964, "longitude": 75.3600476}, format="json")
        self.assertEqual(res2.status_code, status.HTTP_201_CREATED)

        client3 = APIClient()
        client3.force_authenticate(user=self.user3)
        res3 = client3.post(start_url, {"bus_id": self.busC.id, "latitude": 12.0369964, "longitude": 75.3600476}, format="json")
        self.assertEqual(res3.status_code, status.HTTP_201_CREATED)

        # Upload distinct GPS coordinates for each bus
        gps1 = client1.post(update_gps_url, {"latitude": 12.0400, "longitude": 75.3650, "speed": 40.0, "accuracy": 5.0}, format="json")
        self.assertEqual(gps1.status_code, status.HTTP_201_CREATED)

        gps2 = client2.post(update_gps_url, {"latitude": 12.1000, "longitude": 75.4000, "speed": 45.0, "accuracy": 5.0}, format="json")
        self.assertEqual(gps2.status_code, status.HTTP_201_CREATED)

        gps3 = client3.post(update_gps_url, {"latitude": 12.1500, "longitude": 75.4400, "speed": 50.0, "accuracy": 5.0}, format="json")
        self.assertEqual(gps3.status_code, status.HTTP_201_CREATED)

        # Verify GPS logs are strictly isolated per bus
        self.assertEqual(GPSLog.objects.filter(bus=self.busA).last().latitude, 12.0400)
        self.assertEqual(GPSLog.objects.filter(bus=self.busB).last().latitude, 12.1000)
        self.assertEqual(GPSLog.objects.filter(bus=self.busC).last().latitude, 12.1500)

        # Verify passenger latest GPS endpoint yields exact bus data
        client_p = APIClient()
        latest_a = client_p.get(reverse("latest-gps", kwargs={"bus_id": self.busA.id})).json()
        latest_b = client_p.get(reverse("latest-gps", kwargs={"bus_id": self.busB.id})).json()
        latest_c = client_p.get(reverse("latest-gps", kwargs={"bus_id": self.busC.id})).json()

        self.assertEqual(latest_a["latitude"], 12.0400)
        self.assertEqual(latest_b["latitude"], 12.1000)
        self.assertEqual(latest_c["latitude"], 12.1500)

    def test_active_journey_endpoint_and_isolation(self):
        active_url = reverse("active-journey")
        start_url = reverse("start-journey")

        client1 = APIClient()
        client1.force_authenticate(user=self.user1)

        client2 = APIClient()
        client2.force_authenticate(user=self.user2)

        # Initially, neither driver has an active journey
        res1_before = client1.get(active_url).json()
        self.assertFalse(res1_before["has_active_journey"])

        res2_before = client2.get(active_url).json()
        self.assertFalse(res2_before["has_active_journey"])

        # Driver 1 starts Bus A
        res_start1 = client1.post(start_url, {"bus_id": self.busA.id, "latitude": 12.0369964, "longitude": 75.3600476}, format="json")
        self.assertEqual(res_start1.status_code, status.HTTP_201_CREATED)

        # Driver 1 active journey endpoint returns Bus A
        res1_after = client1.get(active_url).json()
        self.assertTrue(res1_after["has_active_journey"])
        self.assertEqual(res1_after["bus_id"], self.busA.id)
        self.assertEqual(res1_after["bus_name"], "Nayana")
        self.assertEqual(res1_after["driver_username"], "driver1")

        # Driver 2 active journey endpoint still returns False (Strict Isolation!)
        res2_after = client2.get(active_url).json()
        self.assertFalse(res2_after["has_active_journey"])

        # Driver 2 starts Bus B
        res_start2 = client2.post(start_url, {"bus_id": self.busB.id, "latitude": 12.0369964, "longitude": 75.3600476}, format="json")
        self.assertEqual(res_start2.status_code, status.HTTP_201_CREATED)

        # Driver 2 active journey endpoint now returns Bus B
        res2_final = client2.get(active_url).json()
        self.assertTrue(res2_final["has_active_journey"])
        self.assertEqual(res2_final["bus_id"], self.busB.id)
        self.assertEqual(res2_final["bus_name"], "Holy Angel")
        self.assertEqual(res2_final["driver_username"], "driver2")


class InactiveBusStateTest(TestCase):

    def setUp(self):
        from django.contrib.auth.models import User
        from .models import Driver, Journey
        self.client = APIClient()
        self.route = Route.objects.create(
            route_name="Thaliparamba - Cherupuzha",
            start_location="Thaliparamba",
            end_location="Cherupuzha",
            total_distance=45.0
        )
        self.stop1 = BusStop.objects.create(route=self.route, stop_order=1, stop_name="Thaliparamba", latitude=12.0369964, longitude=75.3600476)
        self.stop38 = BusStop.objects.create(route=self.route, stop_order=38, stop_name="Cherupuzha", latitude=12.2746351, longitude=75.3637389)

        self.bus1 = Bus.objects.create(bus_name="Bus 1", bus_number="KL-59-A-1001", route=self.route)
        self.bus2 = Bus.objects.create(bus_name="Bus 2", bus_number="KL-59-B-2002", route=self.route)

        self.user1 = User.objects.create_user(username="drv1", password="password")
        self.driver1 = Driver.objects.create(user=self.user1, phone="+919111111111")

        # Create past completed journey and GPS log for Bus 1
        past_j = Journey.objects.create(bus=self.bus1, driver=self.driver1, is_active=False)
        GPSLog.objects.create(bus=self.bus1, journey=past_j, latitude=12.04, longitude=75.37, speed=30.0)

    def test_inactive_bus_latest_gps_returns_inactive(self):
        res = self.client.get(reverse("latest-gps", kwargs={"bus_id": self.bus1.id}))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        data = res.json()
        self.assertFalse(data["active_journey"])
        self.assertIsNone(data["journey_id"])
        self.assertEqual(data["status"], "inactive")

    def test_inactive_bus_eta_returns_empty_polylines_and_inactive(self):
        res = self.client.get(reverse("bus-eta", kwargs={"bus_id": self.bus1.id}))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        data = res.json()
        self.assertFalse(data["active_journey"])
        self.assertEqual(data["status"], "inactive")
        self.assertEqual(data["stops_eta"], [])
        self.assertEqual(data["travelled_polyline"], [])
        self.assertEqual(data["remaining_polyline"], [])
        self.assertIsNone(data["next_stop"])

    def test_journey_lifecycle_and_transition(self):
        driver_client = APIClient()
        driver_client.force_authenticate(user=self.user1)

        # 1. Start journey
        res_start = driver_client.post(
            reverse("start-journey"),
            {"bus_id": self.bus1.id, "latitude": 12.0369964, "longitude": 75.3600476},
            format="json"
        )
        self.assertEqual(res_start.status_code, status.HTTP_201_CREATED)
        j1_id = res_start.json()["id"]

        # 2. Verify active state
        res_eta_active = self.client.get(reverse("bus-eta", kwargs={"bus_id": self.bus1.id})).json()
        self.assertTrue(res_eta_active["active_journey"])
        self.assertEqual(res_eta_active["journey_id"], j1_id)

        # 3. Stop journey
        res_stop = driver_client.post(reverse("stop-journey"))
        self.assertEqual(res_stop.status_code, status.HTTP_200_OK)

        # 4. Verify immediate return to inactive
        res_eta_stopped = self.client.get(reverse("bus-eta", kwargs={"bus_id": self.bus1.id})).json()
        self.assertFalse(res_eta_stopped["active_journey"])
        self.assertEqual(res_eta_stopped["status"], "inactive")

        # 5. Start a second journey
        res_start2 = driver_client.post(
            reverse("start-journey"),
            {"bus_id": self.bus1.id, "latitude": 12.0369964, "longitude": 75.3600476},
            format="json"
        )
        self.assertEqual(res_start2.status_code, status.HTTP_201_CREATED)
        j2_id = res_start2.json()["id"]
        self.assertNotEqual(j1_id, j2_id)

    def test_multi_bus_isolation_active_inactive(self):
        driver_client = APIClient()
        driver_client.force_authenticate(user=self.user1)

        # Start journey on Bus 2 (Bus 1 remains inactive)
        driver_client.post(
            reverse("start-journey"),
            {"bus_id": self.bus2.id, "latitude": 12.0369964, "longitude": 75.3600476},
            format="json"
        )

        res_bus1 = self.client.get(reverse("bus-eta", kwargs={"bus_id": self.bus1.id})).json()
        res_bus2 = self.client.get(reverse("bus-eta", kwargs={"bus_id": self.bus2.id})).json()

        self.assertFalse(res_bus1["active_journey"])
        self.assertEqual(res_bus1["status"], "inactive")

        self.assertTrue(res_bus2["active_journey"])
        self.assertIsNotNone(res_bus2["journey_id"])


