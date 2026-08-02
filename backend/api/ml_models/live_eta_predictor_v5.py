
import numpy as np
import pandas as pd


LIVE_FEATURES_V5 = [
    "speed_mps",
    "accuracy_m",
    "rolling_speed_30s",
    "rolling_speed_60s",
    "progress_speed_30s",
    "progress_speed_60s",
    "is_stopped",
    "is_very_slow",
    "is_slow",
    "is_stopped_30s",
    "is_very_slow_30s",
    "is_slow_30s",
    "is_stopped_60s",
    "is_very_slow_60s",
    "is_slow_60s",
    "direction_code",
    "distance_to_next_stop_m",
]

CONTINUOUS_INDICES_V5 = [0, 1, 2, 3, 4, 5, 16]


def haversine_live_v5(lat1, lon1, lat2, lon2):
    """Great-circle distance in metres."""

    R = 6371000.0

    lat1 = np.radians(float(lat1))
    lon1 = np.radians(float(lon1))
    lat2 = np.radians(float(lat2))
    lon2 = np.radians(float(lon2))

    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = (
        np.sin(dlat / 2.0) ** 2
        + np.cos(lat1)
        * np.cos(lat2)
        * np.sin(dlon / 2.0) ** 2
    )

    c = 2.0 * np.arctan2(
        np.sqrt(a),
        np.sqrt(1.0 - a)
    )

    return float(R * c)


class LiveETAPredictorV5:

    def __init__(
        self,
        model,
        scaler,
        stops,
        direction="forward",
        resample_tolerance_sec=3.5,
        arrival_radius_m=100.0,
        pass_radius_m=150.0,
        history_keep_sec=180.0,
    ):

        self.model = model
        self.scaler = scaler

        self.stops = (
            stops.copy()
            .sort_values("stop_number")
            .reset_index(drop=True)
        )

        direction = direction.lower().strip()
        self.direction = direction

        if direction == "forward":
            self.direction_code = 0.0
            self.current_next_stop_number = 2

        elif direction == "return":
            self.direction_code = 1.0
            self.current_next_stop_number = 37

        else:
            raise ValueError(
                "direction must be 'forward' or 'return'"
            )

        self.resample_tolerance_sec = float(
            resample_tolerance_sec
        )

        self.arrival_radius_m = float(arrival_radius_m)
        self.pass_radius_m = float(pass_radius_m)
        self.history_keep_sec = float(history_keep_sec)

        self.history = pd.DataFrame(
            columns=[
                "time",
                "latitude",
                "longitude",
                "speed_mps",
                "accuracy_m",
            ]
        )


    def reset(self):

        self.history = pd.DataFrame(
            columns=[
                "time",
                "latitude",
                "longitude",
                "speed_mps",
                "accuracy_m",
            ]
        )

        if self.direction == "forward":
            self.current_next_stop_number = 2
        else:
            self.current_next_stop_number = 37


    def next_stop_info(self):

        match = self.stops[
            self.stops["stop_number"]
            == self.current_next_stop_number
        ]

        if len(match) == 0:
            return None

        return match.iloc[0]


    def determine_next_stop(self, latitude, longitude):

        stop = self.next_stop_info()

        if stop is None:
            return None

        distance = haversine_live_v5(
            latitude,
            longitude,
            stop["latitude"],
            stop["longitude"],
        )

        # Move to the following stop after entering
        # the current stop arrival radius.
        if distance <= self.arrival_radius_m:

            if self.direction == "forward":

                if self.current_next_stop_number < 38:
                    self.current_next_stop_number += 1

            else:

                if self.current_next_stop_number > 1:
                    self.current_next_stop_number -= 1

        return self.next_stop_info()



    def _nearest_history_point(self, target_time, max_error_sec=4.0):
        if len(self.history) == 0:
            return None, np.inf

        times = self.history["time"]

        errors = (
            (times - target_time)
            .abs()
            .dt.total_seconds()
        )

        idx = errors.idxmin()
        error = float(errors.loc[idx])

        if error > max_error_sec:
            return None, error

        return self.history.loc[idx], error

    def _window(self, current_time, seconds):
        start = current_time - pd.Timedelta(seconds=seconds)

        window = self.history[
            (self.history["time"] >= start)
            &
            (self.history["time"] <= current_time)
        ]

        return window.copy()

    def _build_features(self, current_time, next_stop):

        point, endpoint_error = self._nearest_history_point(
            current_time,
            max_error_sec=self.resample_tolerance_sec
        )

        if point is None:
            return None

        actual_time = point["time"]

        p30, error30 = self._nearest_history_point(
            actual_time - pd.Timedelta(seconds=30),
            max_error_sec=4.0
        )

        p60, error60 = self._nearest_history_point(
            actual_time - pd.Timedelta(seconds=60),
            max_error_sec=4.0
        )

        if p30 is None or p60 is None:
            return None

        window30 = self._window(
            actual_time,
            30
        )

        window60 = self._window(
            actual_time,
            60
        )

        if len(window30) < 2:
            return None

        if len(window60) < 2:
            return None

        speed = float(point["speed_mps"])
        accuracy = float(point["accuracy_m"])

        rolling_speed_30s = float(
            window30["speed_mps"].mean()
        )

        rolling_speed_60s = float(
            window60["speed_mps"].mean()
        )

        dist30 = haversine_live_v5(
            p30["latitude"],
            p30["longitude"],
            point["latitude"],
            point["longitude"]
        )

        elapsed30 = (
            actual_time - p30["time"]
        ).total_seconds()

        if elapsed30 <= 0:
            return None

        progress_speed_30s = dist30 / elapsed30

        dist60 = haversine_live_v5(
            p60["latitude"],
            p60["longitude"],
            point["latitude"],
            point["longitude"]
        )

        elapsed60 = (
            actual_time - p60["time"]
        ).total_seconds()

        if elapsed60 <= 0:
            return None

        progress_speed_60s = dist60 / elapsed60

        is_stopped = float(
            speed <= 0.5
        )

        is_very_slow = float(
            speed <= 2.0
        )

        is_slow = float(
            speed <= 5.0
        )

        is_stopped_30s = float(
            progress_speed_30s <= 0.5
        )

        is_very_slow_30s = float(
            progress_speed_30s <= 2.0
        )

        is_slow_30s = float(
            progress_speed_30s <= 5.0
        )

        is_stopped_60s = float(
            progress_speed_60s <= 0.5
        )

        is_very_slow_60s = float(
            progress_speed_60s <= 2.0
        )

        is_slow_60s = float(
            progress_speed_60s <= 5.0
        )

        distance_to_next_stop_m = haversine_live_v5(
            point["latitude"],
            point["longitude"],
            next_stop["latitude"],
            next_stop["longitude"]
        )

        features = {
            "speed_mps": speed,
            "accuracy_m": accuracy,

            "rolling_speed_30s": rolling_speed_30s,
            "rolling_speed_60s": rolling_speed_60s,

            "progress_speed_30s": progress_speed_30s,
            "progress_speed_60s": progress_speed_60s,

            "is_stopped": is_stopped,
            "is_very_slow": is_very_slow,
            "is_slow": is_slow,

            "is_stopped_30s": is_stopped_30s,
            "is_very_slow_30s": is_very_slow_30s,
            "is_slow_30s": is_slow_30s,

            "is_stopped_60s": is_stopped_60s,
            "is_very_slow_60s": is_very_slow_60s,
            "is_slow_60s": is_slow_60s,

            "direction_code": self.direction_code,

            "distance_to_next_stop_m":
                distance_to_next_stop_m,
        }

        values = np.array(
            [
                features[f]
                for f in LIVE_FEATURES_V5
            ],
            dtype=np.float32
        )

        if not np.isfinite(values).all():
            return None

        return {
            "features": values,
            "endpoint_error_sec": endpoint_error,
            "error30_sec": error30,
            "error60_sec": error60,
        }





    def _scale_sequence(self, sequence):

        sequence = np.asarray(
            sequence,
            dtype=np.float32
        ).copy()

        original_shape = sequence.shape

        continuous = sequence[
            :,
            CONTINUOUS_INDICES_V5
        ]

        continuous_scaled = self.scaler.transform(
            continuous
        )

        sequence[
            :,
            CONTINUOUS_INDICES_V5
        ] = continuous_scaled

        if sequence.shape != original_shape:
            raise RuntimeError(
                "Scaling changed sequence shape."
            )

        return sequence


    def update(
        self,
        timestamp,
        latitude,
        longitude,
        speed_mps,
        accuracy_m,
    ):

        timestamp = pd.to_datetime(
            timestamp,
            utc=True,
        )

        new_row = pd.DataFrame(
            [{
                "time": timestamp,
                "latitude": float(latitude),
                "longitude": float(longitude),
                "speed_mps": float(speed_mps),
                "accuracy_m": float(accuracy_m),
            }]
        )

        # Avoid concat warning on an empty buffer.
        if len(self.history) == 0:
            self.history = new_row.copy()
        else:
            self.history = pd.concat(
                [self.history, new_row],
                ignore_index=True,
            )

        self.history = (
            self.history
            .sort_values("time")
            .drop_duplicates(
                subset=["time"],
                keep="last",
            )
            .reset_index(drop=True)
        )

        cutoff = timestamp - pd.Timedelta(
            seconds=self.history_keep_sec
        )

        self.history = (
            self.history[
                self.history["time"] >= cutoff
            ]
            .reset_index(drop=True)
        )

        next_stop = self.determine_next_stop(
            latitude,
            longitude,
        )

        if next_stop is None:
            return {
                "status": "route_complete",
                "timestamp": timestamp,
            }

        distance_m = haversine_live_v5(
            latitude,
            longitude,
            next_stop["latitude"],
            next_stop["longitude"],
        )

        history_seconds = (
            self.history["time"].max()
            - self.history["time"].min()
        ).total_seconds()

        if history_seconds < 60:

            return {
                "status": "collecting_history",
                "timestamp": timestamp,
                "history_seconds": float(
                    history_seconds
                ),
                "next_stop_number": int(
                    next_stop["stop_number"]
                ),
                "next_stop": next_stop["stop_name"],
                "distance_m": float(distance_m),
            }

        offsets = np.arange(
            -60,
            1,
            5,
        )

        feature_rows = []
        errors = []

        for offset in offsets:

            feature_time = (
                timestamp
                + pd.Timedelta(seconds=int(offset))
            )

            result = self._build_features(
                feature_time,
                next_stop,
            )

            if result is None:

                return {
                    "status":
                        "feature_history_not_ready",
                    "timestamp": timestamp,
                    "history_seconds": float(
                        history_seconds
                    ),
                    "next_stop_number": int(
                        next_stop["stop_number"]
                    ),
                    "next_stop":
                        next_stop["stop_name"],
                    "distance_m":
                        float(distance_m),
                }

            feature_rows.append(
                result["features"]
            )

            errors.extend([
                result["endpoint_error_sec"],
                result["error30_sec"],
                result["error60_sec"],
            ])

        sequence = np.asarray(
            feature_rows,
            dtype=np.float32,
        )

        if sequence.shape != (13, 17):

            return {
                "status": "invalid_sequence_shape",
                "timestamp": timestamp,
                "shape": sequence.shape,
            }

        if not np.isfinite(sequence).all():

            return {
                "status": "non_finite_sequence",
                "timestamp": timestamp,
            }

        scaled = self._scale_sequence(sequence)

        prediction = self.model.predict(
            scaled[np.newaxis, :, :],
            verbose=0,
        )

        eta_seconds = float(
            prediction.reshape(-1)[0]
        )

        eta_seconds = max(
            0.0,
            eta_seconds,
        )

        return {
            "status": "prediction",
            "timestamp": timestamp,
            "next_stop_number": int(
                next_stop["stop_number"]
            ),
            "next_stop": next_stop["stop_name"],
            "distance_m": float(distance_m),
            "eta_seconds": eta_seconds,
            "eta_minutes": eta_seconds / 60.0,
            "history_seconds": float(
                history_seconds
            ),
            "max_resample_error_sec": (
                float(max(errors))
                if len(errors)
                else 0.0
            ),
        }
