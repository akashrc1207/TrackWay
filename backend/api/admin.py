from django.contrib import admin
from .models import Route, Bus, BusStop, Driver, GPSLog


@admin.register(Route)
class RouteAdmin(admin.ModelAdmin):
    list_display = ("route_name", "start_location", "end_location", "total_distance")
    search_fields = ("route_name",)


@admin.register(Bus)
class BusAdmin(admin.ModelAdmin):
    list_display = ("bus_number", "route", "capacity", "status")
    list_filter = ("status", "route")
    search_fields = ("bus_number",)


@admin.register(BusStop)
class BusStopAdmin(admin.ModelAdmin):
    list_display = ("stop_name", "route", "latitude", "longitude")
    list_filter = ("route",)
    search_fields = ("stop_name",)


@admin.register(Driver)
class DriverAdmin(admin.ModelAdmin):
    list_display = ("user", "phone", "assigned_bus")
    search_fields = ("user__username", "phone")


@admin.register(GPSLog)
class GPSLogAdmin(admin.ModelAdmin):
    list_display = ("bus", "latitude", "longitude", "speed", "timestamp")
    list_filter = ("bus",)
