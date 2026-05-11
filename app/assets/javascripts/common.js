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
  // data 属性側は文字列、polyline.id 側は number で来るので両側を "" 付与で文字列化して比較する。
  function findMapObjectsById(collection, id) {
    const target = id + "";
    return (collection || []).filter(function(obj) { return obj.id + "" === target; });
  }

  // document.body.meta は drawMap() が呼ばれて初めて設定される。
  // マップのないページ（about など）では未定義になるので、安全側で空オブジェクトに寄せる。
  function getMapMeta() {
    return document.body.meta || {};
  }

  // 指定 id を持つ polyline 群を強調表示／元に戻す。
  // リスト側 hover とマップ側 hover の両方から呼ぶので $link ではなく id で受ける。
  function setBusRouteHighlightById(id, highlighted) {
    const polylines = findMapObjectsById(getMapMeta().polylines, id);
    const style = highlighted ? POLYLINE_STYLE_HIGHLIGHTED : POLYLINE_STYLE_NORMAL;
    polylines.forEach(function(polyline) {
      polyline.getServiceObject().setOptions(style);
    });
  }

  // 路線リンクのホバー: data 属性から id を取り出して setBusRouteHighlightById に委譲
  function setBusRouteHighlight($link, highlighted) {
    setBusRouteHighlightById($link.attr("data-bus-route-link"), highlighted);
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
    // ※ reset 側に "click" も含めるのは iOS / Android のタッチ端末対応。
    //    touch では tap で `mouseenter` (合成) → `click` の順に発火するが、
    //    `mouseleave` は安定的に発火しない端末がある。click をフックしておくと
    //    タップで一瞬 highlight された後に確実にリセットでき、ハイライトが
    //    居残るのを防げる。クリックではページ遷移も走るが、ハンドラが先に
    //    実行されるので「reset → 遷移」の順で副作用なし。
    $(document).on("mouseenter", SELECTOR_BUS_ROUTE_LINK, function() {
      setBusRouteHighlight($(this), true);
    });
    $(document).on("mouseleave click", SELECTOR_BUS_ROUTE_LINK, function() {
      setBusRouteHighlight($(this), false);
    });

    // 停留所リンク ↔ marker の連動 (同様に click も含める)
    $(document).on("mouseenter", SELECTOR_BUS_STOP_LINK, function() {
      setBusStopAnimation($(this), google.maps.Animation.BOUNCE);
    });
    $(document).on("mouseleave click", SELECTOR_BUS_STOP_LINK, function() {
      setBusStopAnimation($(this), null);
    });

    // マップ上の polyline 自身に hover した時のハイライト。
    // polyline は drawMap の async コールバック内で初めて生成されるため、
    // application.js がそこで chi-bus:map-ready を trigger する。受け取った時点で
    // Google Maps の mouseover/mouseout listener を attach する。
    $(document).on("chi-bus:map-ready", function() {
      (getMapMeta().polylines || []).forEach(function(polyline) {
        const serviceObject = polyline.getServiceObject();
        google.maps.event.addListener(serviceObject, "mouseover", function() {
          setBusRouteHighlightById(polyline.id, true);
        });
        google.maps.event.addListener(serviceObject, "mouseout", function() {
          setBusRouteHighlightById(polyline.id, false);
        });
        // polyline 自身をクリックしたら対応する bus_route 詳細ページへ遷移
        google.maps.event.addListener(serviceObject, "click", function() {
          window.location.href = "/bus_routes/" + polyline.id;
        });
      });

      // マーカー hover 用の即時 tooltip。Google Maps の Marker は `title` 属性を経由した
      // ネイティブブラウザ tooltip を出すが、500ms 級の遅延があって体感が遅い。
      // 共有 InfoWindow に title 文字列だけ流し込んで mouseover で即開く。
      // ネイティブ tooltip は二重表示防止のために setTitle("") で外す。
      const hoverInfoWindow = new google.maps.InfoWindow({
        disableAutoPan: true,
        headerDisabled: true
      });
      (getMapMeta().markers || []).forEach(function(marker) {
        const serviceObject = marker.getServiceObject();
        const title = serviceObject.getTitle();
        if (!title) return;
        serviceObject.setTitle("");
        // gmaps4rails が marker 生成時に登録した click→InfoWindow ハンドラを外す。
        // クリック時は吹き出しを出さず、直接 marker.path へ遷移させたいため。
        google.maps.event.clearListeners(serviceObject, "click");
        google.maps.event.addListener(serviceObject, "mouseover", function() {
          hoverInfoWindow.setContent(title);
          hoverInfoWindow.open({ map: serviceObject.getMap(), anchor: serviceObject });
        });
        google.maps.event.addListener(serviceObject, "mouseout", function() {
          hoverInfoWindow.close();
        });
        // 通常のバス停 → /bus_stops/:id、Google Places の Place →
        // /bus_stops?position=lat,lng (周辺検索) に飛ぶ。
        // path は build_markers が bus_stop_or_place_path で生成して json に含めている。
        google.maps.event.addListener(serviceObject, "click", function() {
          if (!marker.path) return;
          hoverInfoWindow.close();
          window.location.href = marker.path;
        });
      });
    });
  });
})();
