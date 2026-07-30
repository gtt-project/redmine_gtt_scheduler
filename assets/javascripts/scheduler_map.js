// Colours each resource's route on the run map and lets it be toggled.
//
// redmine_gtt's renderer styles every feature the same way, which for a run map
// means all routes drawn in one colour (a gold that is hard to tell from the
// basemap's own roads) and no way to look at one resource at a time.
//
// Rather than fork the map, this hooks the `gtt:map:ready` event redmine_gtt
// publishes and wraps the vector layer's style function. It is a progressive
// enhancement: if that event or the layer ever stops being available, the map
// still renders exactly as redmine_gtt drew it and no legend is shown, so
// nothing here can break the page.
(function () {
  'use strict';

  var HIDDEN = Object.create(null);

  function asArray(styles) {
    if (!styles) return [];
    return Array.isArray(styles) ? styles : [styles];
  }

  // Clone before recolouring: the style function may hand back shared instances,
  // and mutating those would leak one resource's colour onto everything.
  function recolour(styles, color) {
    return asArray(styles).map(function (style) {
      var copy = typeof style.clone === 'function' ? style.clone() : style;
      var stroke = copy.getStroke && copy.getStroke();
      if (stroke) {
        stroke.setColor(color);
        // Slightly heavier than the default so a route reads against the
        // basemap's own road casings.
        if (typeof stroke.setWidth === 'function') stroke.setWidth(5);
      }
      return copy;
    });
  }

  function wrapStyle(layer) {
    var base = layer.getStyle();
    if (typeof base !== 'function') return false;

    layer.setStyle(function (feature, resolution) {
      // Keyed on the resource id, not its name: names are not unique, so two
      // resources sharing one would otherwise toggle together.
      var id = feature.get('resource_id');
      if (id != null && HIDDEN[id]) return [];

      var styles = base(feature, resolution);
      var color = feature.get('color');
      return color ? recolour(styles, color) : styles;
    });
    return true;
  }

  // One entry per resource on the map, de-duplicated by id and taking the
  // colour from the features themselves, so the legend cannot disagree with
  // what is drawn.
  function resourcesOf(layer) {
    var source = layer.getSource && layer.getSource();
    var features = source && source.getFeatures ? source.getFeatures() : [];
    var seen = Object.create(null);
    var out = [];
    features.forEach(function (feature) {
      var id = feature.get('resource_id');
      if (id == null || seen[id]) return;
      seen[id] = true;
      out.push({
        id: id,
        name: feature.get('resource') || String(id),
        color: feature.get('color')
      });
    });
    return out.sort(function (a, b) { return a.name.localeCompare(b.name); });
  }

  function buildLegend(container, layer, resources) {
    container.innerHTML = '';
    resources.forEach(function (resource) {
      var label = document.createElement('label');
      label.className = 'scheduler-map-legend-item';

      var box = document.createElement('input');
      box.type = 'checkbox';
      box.checked = !HIDDEN[resource.id];
      box.addEventListener('change', function () {
        if (box.checked) delete HIDDEN[resource.id];
        else HIDDEN[resource.id] = true;
        layer.changed();
      });

      var swatch = document.createElement('span');
      swatch.className = 'scheduler-map-legend-swatch';
      if (resource.color) swatch.style.background = resource.color;

      label.appendChild(box);
      label.appendChild(swatch);
      label.appendChild(document.createTextNode(resource.name));
      container.appendChild(label);
    });
    container.hidden = resources.length === 0;
  }

  document.addEventListener('gtt:map:ready', function (event) {
    var container = document.getElementById('scheduler-map-legend');
    if (!container) return;

    var client = event.detail && event.detail.client;
    var layer = client && client.vector;
    if (!layer || !wrapStyle(layer)) return;

    buildLegend(container, layer, resourcesOf(layer));
    layer.changed();
  });
})();
