import os, sys, django
sys.path.append('/home/akashchandranakd/TrackWay/backend')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'trackway.settings')
django.setup()

from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from api.models import Driver
from api.views import login_driver
from django.test import RequestFactory

print("=== 1. VERIFY USER RECORDS ===")
for u_name in ["driver1", "driver2", "driver3"]:
    exists = User.objects.filter(username=u_name).exists()
    print(f"User '{u_name}' exists: {exists}")
    if exists:
        u = User.objects.get(username=u_name)
        print(f"   User ID: {u.id}, is_active: {u.is_active}, password_set: {u.has_usable_password()}")

print("\n=== 2. VERIFY DRIVER RECORDS ===")
for u_name in ["driver1", "driver2", "driver3"]:
    exists = Driver.objects.filter(user__username=u_name).exists()
    print(f"Driver for '{u_name}' exists: {exists}")

print("\n=== 3. PRINT EVERY DRIVER IN DB ===")
drivers = list(Driver.objects.select_related("user").values("id", "user__username", "assigned_bus_id"))
for d in drivers:
    print(d)

print("\n=== 4. VERIFY PASSWORDS (authenticate()) ===")
for u_name in ["driver1", "driver2", "driver3"]:
    auth_user = authenticate(username=u_name, password="driver123")
    print(f"authenticate('{u_name}', 'driver123'): {auth_user}")

print("\n=== 5. TEST API POST /api/auth/login/ ===")
factory = RequestFactory()
for u_name in ["driver1", "driver2", "driver3"]:
    req = factory.post(
        "/api/auth/login/",
        data={"username": u_name, "password": "driver123"},
        content_type="application/json"
    )
    res = login_driver(req)
    print(f"\nLogin attempt for '{u_name}':")
    print(f"  HTTP Status: {res.status_code}")
    print(f"  Response JSON: {res.data}")
