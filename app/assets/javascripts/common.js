(function() {
  function listResize() {
    if (!$(".list-window").length) return;
    $(".map").height($(window).height() - 125);
    if ($(window).width() < 768 || window.matchMedia("print").matches) {
      $(".list-window").height("auto");
      $(".list-window").css("overflow-y", "visible");
    } else {
      var listWindowHeight = $(window).height() - $(".list-window").offset().top - 11;
      $(".list-window").height(listWindowHeight);
      $(".list-window").css("overflow-y", "scroll");
    }
  }

  $(function() {
    $("button[data-geolocation]").click(function(e) {
      // q が入力されているときは通常のキーワード検索なので位置情報取得をスキップ
      if ($(this).closest("form").find("#q").val() !== "") return;
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(function(position) {
          var lat = position.coords.latitude;
          var long = position.coords.longitude;
          window.location.href = "/bus_stops?position=" + lat + "," + long;
        }, function(err) {
          console.warn("ERROR(" + err.code + "): " + err.message);
        });
      } else {
        console.warn("Navigator.geolocation not supported.");
      }
      return false;
    });
  });

  $(function() {
    $("a[data-search-map-center]").click(function(e) {
      var center = handler.getMap().getCenter();
      var lat = center.lat();
      var long = center.lng();
      window.location.href = "/bus_stops?position=" + lat + "," + long;
      return false;
    });
  });

  $(function() {
    listResize();
    $(window).resize(function() {
      listResize();
    });
    var mql = window.matchMedia("print");
    mql.addListener(function(mql) {
      if (mql.matches) {
        listResize();
      }
    });
  });

  $(function() {
    function setPolylineOptions(object, strokeColor, strokeOpacity, zIndex) {
      var id = $(object).attr("data-bus-route-link");
      if (!document.body.meta.polylines) return;
      for (var i = 0; i < document.body.meta.polylines.length; i++) {
        var polyline = document.body.meta.polylines[i];
        if (polyline.id + "" === id) {
          polyline.getServiceObject().setOptions({
            strokeColor: strokeColor,
            strokeOpacity: strokeOpacity,
            zIndex: zIndex
          });
        }
      }
    }
    $("a[data-bus-route-link]").on("mouseenter", function(e) {
      setPolylineOptions(this, "#c00", 1.0, 1);
    });
    $("a[data-bus-route-link]").on("mouseleave click", function(e) {
      setPolylineOptions(this, "#00f", 0.5, 0);
    });
  });

  $(function() {
    function setMarkerAnimation(object, animation) {
      var id = $(object).attr("data-bus-stop-link");
      if (!document.body.meta.markers) return;
      for (var i = 0; i < document.body.meta.markers.length; i++) {
        var marker = document.body.meta.markers[i];
        if (marker.id + "" === id) {
          marker.getServiceObject().setAnimation(animation);
        }
      }
    }
    $("a[data-bus-stop-link]").on("mouseenter", function(e) {
      setMarkerAnimation(this, google.maps.Animation.BOUNCE);
    });
    $("a[data-bus-stop-link]").on("mouseleave click", function(e) {
      setMarkerAnimation(this, null);
    });
  });
})();
