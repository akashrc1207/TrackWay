from django.contrib import admin
from .models import Route, Bus, BusStop, Driver, GPSLog

admin.site.register(Route)
admin.site.register(Bus)
admin.site.register(BusStop)
admin.site.register(Driver)
admin.site.register(GPSLog)