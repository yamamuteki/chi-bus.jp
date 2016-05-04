// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or any plugin's vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require jquery
//= require jquery_ujs
//= require bootstrap-sprockets
//= require underscore-min
//= require gmaps/google
//= require jquery.turbolinks
//= require turbolinks
//= require_tree .

function drawMap(markersJson, polylinesJson, busStopsCount, centerMakerImagePath) {
  if (!document.body.meta) { document.body.meta = new Object(); }
  handler = Gmaps.build('Google');
  handler.buildMap({ provider: { scrollwheel: false, MinZoom:15 }, internal: {id: 'map'}}, function(){
    var markers = $.map(markersJson, function(busStop){
      var marker = handler.addMarker(busStop);
      marker.id = busStop.id;
      return marker;
    });
    document.body.meta.markers = markers;
    if (polylinesJson) {
      var polylines = $.map(polylinesJson, function(busRoute){
        var polyline = handler.addPolylines(busRoute['tracks'], { strokeColor: '#00f', strokeOpacity: 0.5 });
        $.each(polyline, function(){ this.id = busRoute['id'] });
        return polyline;
      });
      document.body.meta.polylines = polylines;
      handler.bounds.extendWith(polylines);
    } else {
      handler.bounds.extendWith(markers);
    }
    handler.fitMapToBounds();
    centerMarker = handler.addMarker({
      "lat": handler.getMap().getCenter().lat(),
      "lng": handler.getMap().getCenter().lng(),
      "picture": {
        "url": centerMakerImagePath,
        "width":  32,
        "height": 32
      },
    });
    google.maps.event.addListener(handler.getMap(), 'center_changed', function(){
      centerMarker.getServiceObject().setPosition(this.getCenter());
    });
    if (busStopsCount == 1 && !polylinesJson) {
      handler.getMap().setZoom(15);
    }
  });
}
