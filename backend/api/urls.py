from django.urls import path
from . import views

urlpatterns = [
    path("routes/", views.route_list, name="route-list"),
    path("buses/", views.bus_list, name="bus-list"),
    path("drivers/", views.driver_list, name="driver-list"),
]