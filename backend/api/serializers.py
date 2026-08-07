from rest_framework import serializers
from .models import Route, Bus, BusStop, Driver, GPSLog, Journey


class RouteSerializer(serializers.ModelSerializer):
    class Meta:
        model = Route
        fields = "__all__"


class BusSerializer(serializers.ModelSerializer):
    route_name = serializers.CharField(source="route.route_name", read_only=True)
    start_location = serializers.CharField(source="route.start_location", read_only=True)
    end_location = serializers.CharField(source="route.end_location", read_only=True)
    status = serializers.SerializerMethodField()
    active_journey = serializers.SerializerMethodField()
    active_journey_id = serializers.SerializerMethodField()

    def get_status(self, obj):
        has_active_journey = Journey.objects.filter(bus=obj, is_active=True).exists()
        return "Active" if has_active_journey else "Inactive"

    def get_active_journey(self, obj):
        return Journey.objects.filter(bus=obj, is_active=True).exists()

    def get_active_journey_id(self, obj):
        j = Journey.objects.filter(bus=obj, is_active=True).first()
        return j.id if j else None

    class Meta:
        model = Bus
        fields = "__all__"


class BusStopSerializer(serializers.ModelSerializer):
    class Meta:
        model = BusStop
        fields = "__all__"


class DriverSerializer(serializers.ModelSerializer):
    class Meta:
        model = Driver
        fields = "__all__"


class GPSLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = GPSLog
        fields = "__all__"

class JourneySerializer(serializers.ModelSerializer):
    class Meta:
        model = Journey
        fields = "__all__"

class RouteDetailSerializer(serializers.ModelSerializer):
    stops = BusStopSerializer(source="busstop_set", many=True)

    class Meta:
        model = Route
        fields = (
            "id",
            "route_name",
            "start_location",
            "end_location",
            "total_distance",
            "stops",
        )