from django.db import models
from django.contrib.auth.models import User


class Route(models.Model):
    route_name = models.CharField(max_length=100)
    start_location = models.CharField(max_length=100)
    end_location = models.CharField(max_length=100)
    total_distance = models.FloatField()

    def __str__(self):
        return self.route_name


class Bus(models.Model):
    bus_name = models.CharField(max_length=100, default="")
    bus_number = models.CharField(max_length=20, unique=True)
    capacity = models.PositiveIntegerField(default=50)
    route = models.ForeignKey(Route, on_delete=models.CASCADE)
    status = models.CharField(max_length=20, default="Active")

    def __str__(self):
        return f"{self.bus_name} ({self.bus_number})" if self.bus_name else self.bus_number


class BusStop(models.Model):
    stop_name = models.CharField(max_length=100)
    latitude = models.FloatField()
    longitude = models.FloatField()
    route = models.ForeignKey(Route, on_delete=models.CASCADE)
    stop_order = models.PositiveIntegerField(default=1)

    class Meta:
        ordering = ['stop_order']

    def __str__(self):
        return f"{self.stop_order}. {self.stop_name}"


class Driver(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    phone = models.CharField(max_length=15, unique=True)
    assigned_bus = models.OneToOneField(
        Bus,
        on_delete=models.SET_NULL,
        null=True,
        blank=True
    )

    def __str__(self):
        return self.user.get_full_name() or self.user.username

class Journey(models.Model):
    bus = models.ForeignKey(Bus, on_delete=models.CASCADE)
    driver = models.ForeignKey(Driver, on_delete=models.CASCADE)

    start_time = models.DateTimeField(auto_now_add=True)
    end_time = models.DateTimeField(null=True, blank=True)

    is_active = models.BooleanField(default=True)

    def __str__(self):
        return f"{self.bus.bus_number} - {self.start_time}"

class GPSLog(models.Model):
    bus = models.ForeignKey(Bus, on_delete=models.CASCADE)
    journey = models.ForeignKey(
    Journey,
    on_delete=models.CASCADE,
    null=True,
    blank=True
)
    latitude = models.FloatField()
    longitude = models.FloatField()
    speed = models.FloatField()
    timestamp = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.bus.bus_number} - {self.timestamp}"