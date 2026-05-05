// 全画面共通の挙動をまとめたスクリプト。
// IIFE（即時実行関数）でグローバル汚染を防ぎつつ、ページ内のクリックやリサイズに対する
// jQuery のイベントハンドラをまとめて登録している。
(function() {
  // ---------------------------------------------------------------------------
  // セレクタ定数
  // 同じセレクタを複数箇所で書くと typo の温床になるので、上で一度だけ定義しておく。
  // ---------------------------------------------------------------------------
  const SELECTOR_GEOLOCATION_BUTTON = "button[data-geolocation]";
  const SELECTOR_SEARCH_MAP_CENTER = "a[data-search-map-center]";
  const SELECTOR_BUS_ROUTE_LINK = "a[data-bus-route-link]";
  const SELECTOR_BUS_STOP_LINK = "a[data-bus-stop-link]";

  // ---------------------------------------------------------------------------
  // マップ図形のスタイル定数
  // Google Maps の Polyline / Marker は SVG/Canvas 描画なので CSS クラスは効かない。
  // 代わりに「JS のオプション値オブジェクト」を名前付きで切り出して使い回す。
  // ---------------------------------------------------------------------------
  // 路線（Polyline）のスタイル
  const POLYLINE_STYLE_NORMAL = {
    strokeColor: "#00f",   // 青
    strokeOpacity: 0.5,    // 半透明
    zIndex: 0
  };
  const POLYLINE_STYLE_HIGHLIGHTED = {
    strokeColor: "#c00",   // 赤
    strokeOpacity: 1.0,    // 不透明
    zIndex: 1              // 他の路線の上に重ねる
  };

  // ---------------------------------------------------------------------------
  // 現在地検索ボタン: navigator.geolocation で緯度経度を取って /bus_stops?position=... へ遷移
  // ---------------------------------------------------------------------------
  function handleGeolocationClick(event) {
    // 同じフォーム内のキーワード入力 (#q) に値があるなら、ユーザーはキーワード検索を意図している。
    // その場合は現在地取得をスキップしてフォームを通常送信させる。
    const $form = $(this).closest("form");
    if ($form.find("#q").val() !== "") return;

    event.preventDefault();

    if (!navigator.geolocation) {
      console.warn("Navigator.geolocation not supported.");
      return;
    }

    navigator.geolocation.getCurrentPosition(
      function(position) {
        const lat = position.coords.latitude;
        const lng = position.coords.longitude;
        window.location.href = "/bus_stops?position=" + lat + "," + lng;
      },
      function(err) {
        console.warn("ERROR(" + err.code + "): " + err.message);
      }
    );
  }

  // ---------------------------------------------------------------------------
  // 「この地図の中心で検索」リンク: 表示中のマップの中心座標で検索画面へ遷移
  // ---------------------------------------------------------------------------
  function handleSearchMapCenterClick(event) {
    event.preventDefault();
    // handler は application.js の drawMap() 内で生成されるグローバル変数。
    const center = handler.getMap().getCenter();
    window.location.href = "/bus_stops?position=" + center.lat() + "," + center.lng();
  }

  // ---------------------------------------------------------------------------
  // ホバー連動: リスト項目とマップ上の図形（polyline / marker）を同期させる
  // ---------------------------------------------------------------------------
  // data-* 属性に入っている id と一致する Gmaps オブジェクトを「全部」返す。
  // application.js は 1 つの bus_route に対して複数の polyline（tracks の数だけ）を作ることがあり、
  // 同じ id を共有している。ホバー時はそれら全部を一括で強調表示したいので、find（最初の 1 件）ではなく filter を使う。
  // marker は 1 つの bus_stop につき 1 つだけだが、コードを揃えるため同じ関数で扱う。
  // data 属性は文字列で取り出されるので "+ ''" で文字列化して比較している。
  function findMapObjectsById(collection, id) {
    return (collection || []).filter(function(obj) { return obj.id + "" === id; });
  }

  // document.body.meta は drawMap() が呼ばれて初めて設定される。
  // マップのないページ（about など）では未定義になるので、安全側で空オブジェクトに寄せる。
  function getMapMeta() {
    return document.body.meta || {};
  }

  // 路線リンクのホバー: 対応する polyline 群を強調表示／元に戻す
  function setBusRouteHighlight($link, highlighted) {
    const id = $link.attr("data-bus-route-link");
    const polylines = findMapObjectsById(getMapMeta().polylines, id);
    const style = highlighted ? POLYLINE_STYLE_HIGHLIGHTED : POLYLINE_STYLE_NORMAL;
    polylines.forEach(function(polyline) {
      polyline.getServiceObject().setOptions(style);
    });
  }

  // 停留所リンクのホバー: 対応する marker をバウンスさせる／止める
  function setBusStopAnimation($link, animation) {
    const id = $link.attr("data-bus-stop-link");
    const markers = findMapObjectsById(getMapMeta().markers, id);
    markers.forEach(function(marker) {
      marker.getServiceObject().setAnimation(animation);
    });
  }

  // ---------------------------------------------------------------------------
  // DOMContentLoaded 後に各種イベントハンドラを登録
  // ---------------------------------------------------------------------------
  $(function() {
    // 検索系
    $(document).on("click", SELECTOR_GEOLOCATION_BUTTON, handleGeolocationClick);
    $(document).on("click", SELECTOR_SEARCH_MAP_CENTER, handleSearchMapCenterClick);

    // 路線リンク ↔ polyline の連動
    $(document).on("mouseenter", SELECTOR_BUS_ROUTE_LINK, function() {
      setBusRouteHighlight($(this), true);
    });
    $(document).on("mouseleave", SELECTOR_BUS_ROUTE_LINK, function() {
      setBusRouteHighlight($(this), false);
    });

    // 停留所リンク ↔ marker の連動
    $(document).on("mouseenter", SELECTOR_BUS_STOP_LINK, function() {
      setBusStopAnimation($(this), google.maps.Animation.BOUNCE);
    });
    $(document).on("mouseleave", SELECTOR_BUS_STOP_LINK, function() {
      setBusStopAnimation($(this), null);
    });
  });
})();
