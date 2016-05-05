# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/
$ ->
  $("button[data-geolocation]").click (e) ->
    return if $(this).closest("form").find("#q").val() != '' # keyword search
    if (navigator.geolocation)
      navigator.geolocation.getCurrentPosition(success, error)
    else
      console.warn('Navigator.geolocation not supported.')
    false

success = (position) ->
  lat = position.coords.latitude
  long = position.coords.longitude
  window.location.href = '/bus_stops/?position=' + lat + ',' + long

error = (err) ->
  console.warn('ERROR(' + err.code + '): ' + err.message)

$ ->
  $("a[data-search-map-center]").click (e) ->
    center = handler.getMap().getCenter()
    lat = center.lat()
    long = center.lng()
    window.location.href = '/bus_stops/?position=' + lat + ',' + long
    false

$ ->
  $("input[data-toggle-draggable]").change (e) ->
    value = $(this).prop('checked')
    handler.getMap().setOptions({draggable: !value})
  $("input[data-toggle-draggable]").prop("checked", from_smartphone()).change()

$(document).on 'page:fetch', ->
  $(".turbolinks-loading").show()
  return

$(document).on 'page:change', ->
  $(".turbolinks-loading").fadeOut 100
  return

$ ->
  listResize()
  $(window).resize ->
    listResize()

listResize = ->
  return unless $(".list-window").length
  $(".map").height($(window).height() - 120)
  if $(window).width() < 768
    $(".list-window").height("auto")
    $(".list-window").css("overflow-y", "visible")
  else
    $(".list-window").height($(window).height() - $(".list-window").offset().top - 10)
    $(".list-window").css("overflow-y", "scroll")

$ ->
  $("a[data-bus-route-link]").on 'mouseenter', (e) ->
    id = $(this).attr('data-bus-route-link')
    return unless document.body.meta.polylines
    for polyline in document.body.meta.polylines
      if polyline.id + '' == id
        polyline.getServiceObject().setOptions({ strokeColor: '#c00', strokeOpacity: 1.0, zIndex: 1 })
  $("a[data-bus-route-link]").on 'mouseleave click', (e) ->
    id = $(this).attr('data-bus-route-link')
    return unless document.body.meta.polylines
    for polyline in document.body.meta.polylines
      if polyline.id + '' == id
        polyline.getServiceObject().setOptions({ strokeColor: '#00f', strokeOpacity: 0.5, zIndex: 0 })

$ ->
  $("a[data-bus-stop-link]").on 'mouseenter', (e) ->
    id = $(this).attr('data-bus-stop-link')
    return unless document.body.meta.markers
    for marker in document.body.meta.markers
      if marker.id + '' == id
        marker.getServiceObject().setAnimation(google.maps.Animation.BOUNCE)
  $("a[data-bus-stop-link]").on 'mouseleave click', (e) ->
    id = $(this).attr('data-bus-stop-link')
    return unless document.body.meta.markers
    for marker in document.body.meta.markers
      if marker.id + '' == id
        marker.getServiceObject().setAnimation(null)

