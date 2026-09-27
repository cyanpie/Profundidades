// Pipeline de sprites de Profundidades para ComfyUI (GDD §10).
// Se ejecuta dentro de la página de ComfyUI (http://127.0.0.1:8188), así usa su API sin CORS:
//   1. Encola un workflow SDXL + LoRA pixel-art-xl por asset (2 candidatos cada uno).
//   2. Posprocesa cada imagen en un canvas:
//      - objetos: quita el fondo (flood fill desde los bordes), conserva solo el objeto más grande
//        (descarta sombras y objetos sueltos), recorta y centra;
//      - bloques: recorta el centro para ampliar la textura (menos detalle, píxeles más gordos);
//      - agrupa colores con k-means y los asigna a colores distintos de la paleta Endesga 32;
//      - reduce al tamaño final eligiendo el color mayoritario de cada celda (no promedia: conserva contraste);
//      - a los objetos les añade un contorno oscuro de 1 px para que se lean sobre cualquier fondo.
//   3. Devuelve PNGs diminutos en base64 (32×32 o 16×16) listos para el juego.
//
// Uso (desde la consola de ComfyUI o una herramienta que ejecute JS en la página):
//   SpritePipeline.queueAll(catalogo.assets, catalogo.style)   // catálogo = tools/sprites/assets.json
//   await SpritePipeline.collect()                              // repetir hasta que pending sea 0

(() => {
	const ENDESGA32 = [
		"be4a2f", "d77643", "ead4aa", "e4a672", "b86f50", "733e39", "3e2731", "a22633",
		"e43b44", "f77622", "feae34", "fee761", "63c74d", "3e8948", "265c42", "193c3e",
		"124e89", "0099db", "2ce8f5", "ffffff", "c0cbdc", "8b9bb4", "5a6988", "3a4466",
		"262b44", "181425", "ff0044", "68386c", "b55088", "f6757a", "e8b796", "c28569",
	].map((h) => [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]);
	const OUTLINE = [0x18, 0x14, 0x25];

	const CONFIG = {
		checkpoint: "sd_xl_base_1.0.safetensors",
		lora: "pixel-art-xl.safetensors",
		loraStrength: 1.0,
		steps: 28,
		cfg: 6.0,
		sampler: "dpmpp_2m",
		scheduler: "karras",
		resolution: 1024,
		candidates: 2,
		bgTolerance: 56,      // distancia RGB máxima para considerar un píxel "fondo" (incluye sombras suaves)
		coverage: 0.4,        // fracción mínima de píxeles opacos para que una celda final sea opaca
		padding: 0.04,        // margen alrededor del objeto al recortar (fracción del lado)
		tileZoom: 0.45,       // fracción central de la imagen que se usa para los bloques
		objectColors: 7,      // colores (clusters) por objeto, sin contar el contorno
		tileColors: 5,        // colores por bloque
		altColorSlack: 3.0,   // cuánto más lejos puede estar un color alternativo para no repetir colores
	};

	const state = { jobs: {}, clientId: "profundidades-" + Math.random().toString(36).slice(2) };

	function workflow(asset, style) {
		const suffix = asset.transparent ? style.object_suffix : style.tile_suffix;
		const positive = `${style.positive}, ${asset.prompt}, ${suffix}`;
		const typeNegative = asset.transparent ? style.object_negative : style.tile_negative;
		const negative = [style.negative, asset.replace_type_negative ? null : typeNegative, asset.negative]
			.filter(Boolean).join(", ");
		return {
			"4": { class_type: "CheckpointLoaderSimple", inputs: { ckpt_name: CONFIG.checkpoint } },
			"10": { class_type: "LoraLoader", inputs: { model: ["4", 0], clip: ["4", 1], lora_name: CONFIG.lora,
				strength_model: CONFIG.loraStrength, strength_clip: CONFIG.loraStrength } },
			"6": { class_type: "CLIPTextEncode", inputs: { clip: ["10", 1], text: positive } },
			"7": { class_type: "CLIPTextEncode", inputs: { clip: ["10", 1], text: negative } },
			"5": { class_type: "EmptyLatentImage", inputs: { width: CONFIG.resolution, height: CONFIG.resolution,
				batch_size: CONFIG.candidates } },
			"3": { class_type: "KSampler", inputs: { model: ["10", 0], positive: ["6", 0], negative: ["7", 0],
				latent_image: ["5", 0], seed: asset.seed, steps: CONFIG.steps, cfg: CONFIG.cfg,
				sampler_name: CONFIG.sampler, scheduler: CONFIG.scheduler, denoise: 1.0 } },
			"8": { class_type: "VAEDecode", inputs: { samples: ["3", 0], vae: ["4", 2] } },
			"9": { class_type: "SaveImage", inputs: { images: ["8", 0], filename_prefix: `profundidades/${asset.category}/${asset.id}` } },
		};
	}

	async function queueAll(assets, style) {
		const queued = [];
		for (const asset of assets) {
			const r = await fetch("/prompt", {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify({ prompt: workflow(asset, style), client_id: state.clientId }),
			});
			const j = await r.json();
			if (!r.ok || !j.prompt_id) throw new Error(`No se pudo encolar ${asset.id}: ${JSON.stringify(j).slice(0, 300)}`);
			state.jobs[asset.id] = { asset, promptId: j.prompt_id, done: false, urls: [] };
			queued.push(asset.id);
		}
		return queued;
	}

	// Devuelve los assets terminados desde la última llamada: { id: [dataURL, ...] } y cuántos quedan.
	async function collect(limit = Infinity) {
		const out = {};
		let pending = 0, taken = 0;
		for (const job of Object.values(state.jobs)) {
			if (job.done) continue;
			if (taken >= limit) { pending++; continue; }
			const h = await fetch(`/history/${job.promptId}`).then((r) => r.json());
			const entry = h[job.promptId];
			if (!entry) { pending++; continue; }
			job.done = true;
			taken++;
			if (entry.status && entry.status.status_str === "error") {
				out[job.asset.id] = { error: JSON.stringify(entry.status.messages || []).slice(0, 300) };
				continue;
			}
			const images = entry.outputs?.["9"]?.images || [];
			job.urls = images.map((im) =>
				`/view?filename=${encodeURIComponent(im.filename)}&subfolder=${encodeURIComponent(im.subfolder)}&type=${im.type}`);
			out[job.asset.id] = [];
			for (const url of job.urls) out[job.asset.id].push(await processImage(url, job.asset));
		}
		return { results: out, pending };
	}

	// Vuelve a posprocesar lo ya generado (útil al ajustar CONFIG sin regenerar en la GPU).
	async function reprocess(ids) {
		const out = {};
		for (const id of ids) {
			const job = state.jobs[id];
			if (!job || !job.urls.length) continue;
			out[id] = [];
			for (const url of job.urls) out[id].push(await processImage(url, job.asset));
		}
		return out;
	}

	async function processImage(url, asset) {
		const size = asset.size, transparent = asset.transparent;
		const bmp = await createImageBitmap(await (await fetch(url)).blob());
		const W = bmp.width, H = bmp.height;
		const c = new OffscreenCanvas(W, H);
		const ctx = c.getContext("2d");
		ctx.drawImage(bmp, 0, 0);
		const px = ctx.getImageData(0, 0, W, H).data;
		const opaque = new Uint8Array(W * H).fill(1);

		let x0, y0, side, inner;
		if (transparent) {
			removeBackground(px, W, H, opaque);
			keepLargestComponent(opaque, W, H);
			const box = bbox(opaque, W, H);
			if (!box) return null;
			const w = box.x1 - box.x0 + 1, h = box.y1 - box.y0 + 1;
			side = Math.ceil(Math.max(w, h) * (1 + 2 * CONFIG.padding));
			x0 = Math.round(box.x0 + w / 2 - side / 2);
			y0 = Math.round(box.y0 + h / 2 - side / 2);
			inner = size - 2; // 1 px por lado para el contorno
		} else {
			side = Math.round(Math.min(W, H) * CONFIG.tileZoom);
			x0 = Math.round((W - side) / 2);
			y0 = Math.round((H - side) / 2);
			inner = size;
		}

		const k = transparent ? CONFIG.objectColors : CONFIG.tileColors;
		const { labels, colors } = quantize(px, opaque, W, H, x0, y0, side, k);
		let rgba = majorityDownscale(labels, colors, opaque, W, H, x0, y0, side, inner);
		if (transparent) rgba = addOutline(rgba, inner, size);
		return encode(rgba, size);
	}

	function removeBackground(px, W, H, opaque) {
		const bg = cornerColor(px, W, H);
		const tol2 = CONFIG.bgTolerance * CONFIG.bgTolerance;
		const isBg = (i) => {
			const dr = px[i * 4] - bg[0], dg = px[i * 4 + 1] - bg[1], db = px[i * 4 + 2] - bg[2];
			return dr * dr + dg * dg + db * db <= tol2;
		};
		const stack = [];
		for (let x = 0; x < W; x++) stack.push(x, (H - 1) * W + x);
		for (let y = 0; y < H; y++) stack.push(y * W, y * W + W - 1);
		while (stack.length) {
			const i = stack.pop();
			if (!opaque[i] || !isBg(i)) continue;
			opaque[i] = 0;
			const x = i % W, y = (i / W) | 0;
			if (x > 0) stack.push(i - 1);
			if (x < W - 1) stack.push(i + 1);
			if (y > 0) stack.push(i - W);
			if (y < H - 1) stack.push(i + W);
		}
	}

	// Deja solo la región opaca conectada más grande (quita sombras, chispas y objetos extra).
	function keepLargestComponent(opaque, W, H) {
		const comp = new Int32Array(W * H).fill(-1);
		let best = -1, bestSize = 0, id = 0;
		const stack = [];
		for (let s = 0; s < W * H; s++) {
			if (!opaque[s] || comp[s] !== -1) continue;
			let n = 0;
			stack.push(s);
			comp[s] = id;
			while (stack.length) {
				const i = stack.pop(); n++;
				const x = i % W, y = (i / W) | 0;
				const nb = [x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1, y > 0 ? i - W : -1, y < H - 1 ? i + W : -1];
				for (const j of nb) if (j >= 0 && opaque[j] && comp[j] === -1) { comp[j] = id; stack.push(j); }
			}
			if (n > bestSize) { bestSize = n; best = id; }
			id++;
		}
		for (let i = 0; i < W * H; i++) if (opaque[i] && comp[i] !== best) opaque[i] = 0;
	}

	function cornerColor(px, W, H) {
		const s = [0, 0, 0]; let n = 0;
		for (const [cx, cy] of [[0, 0], [W - 8, 0], [0, H - 8], [W - 8, H - 8]])
			for (let y = cy; y < cy + 8; y++) for (let x = cx; x < cx + 8; x++) {
				const i = (y * W + x) * 4; s[0] += px[i]; s[1] += px[i + 1]; s[2] += px[i + 2]; n++;
			}
		return s.map((v) => v / n);
	}

	function bbox(opaque, W, H) {
		let x0 = W, y0 = H, x1 = -1, y1 = -1;
		for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (opaque[y * W + x]) {
			if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
		}
		return x1 < 0 ? null : { x0, y0, x1, y1 };
	}

	// k-means sobre los píxeles opacos de la región; cada cluster recibe un color distinto de la paleta.
	function quantize(px, opaque, W, H, x0, y0, side, k) {
		const samples = [];
		const step = Math.max(1, Math.floor(side / 160));
		for (let y = y0; y < y0 + side; y += step) for (let x = x0; x < x0 + side; x += step) {
			if (x < 0 || y < 0 || x >= W || y >= H) continue;
			const i = y * W + x;
			if (opaque[i]) samples.push([px[i * 4], px[i * 4 + 1], px[i * 4 + 2]]);
		}
		k = Math.max(1, Math.min(k, samples.length));
		// Inicialización k-means++ determinista (siempre elige el punto más lejano).
		const centers = [samples[0].slice()];
		while (centers.length < k) {
			let far = samples[0], fd = -1;
			for (const s of samples) {
				let d = Infinity;
				for (const c of centers) d = Math.min(d, dist2(s, c));
				if (d > fd) { fd = d; far = s; }
			}
			centers.push(far.slice());
		}
		const counts = new Array(k).fill(0);
		for (let it = 0; it < 12; it++) {
			const acc = centers.map(() => [0, 0, 0]); counts.fill(0);
			for (const s of samples) {
				const c = nearestIndex(s, centers);
				acc[c][0] += s[0]; acc[c][1] += s[1]; acc[c][2] += s[2]; counts[c]++;
			}
			for (let c = 0; c < k; c++) if (counts[c]) centers[c] = acc[c].map((v) => v / counts[c]);
		}
		// Asigna a cada cluster (de mayor a menor) su color de paleta más cercano. Si ya lo usa otro
		// cluster, prueba el siguiente más cercano solo si no se aleja demasiado del tono original;
		// así se conserva el contraste sin inventar colores ajenos (p. ej. violetas en la tierra).
		const order = [...centers.keys()].sort((a, b) => counts[b] - counts[a]);
		const used = new Set(), colors = new Array(k);
		for (const c of order) {
			const ranked = ENDESGA32.map((p, pi) => [redmean(centers[c], p), pi]).sort((a, b) => a[0] - b[0]);
			let pick = ranked[0][1];
			if (used.has(pick)) {
				const alt = ranked.find(([d, pi]) => !used.has(pi));
				if (alt && alt[0] <= ranked[0][0] * CONFIG.altColorSlack + 2000) pick = alt[1];
			}
			used.add(pick);
			colors[c] = ENDESGA32[pick];
		}
		const labels = new Int8Array(W * H).fill(-1);
		for (let y = Math.max(0, y0); y < Math.min(H, y0 + side); y++)
			for (let x = Math.max(0, x0); x < Math.min(W, x0 + side); x++) {
				const i = y * W + x;
				if (opaque[i]) labels[i] = nearestIndex([px[i * 4], px[i * 4 + 1], px[i * 4 + 2]], centers);
			}
		return { labels, colors };
	}

	function majorityDownscale(labels, colors, opaque, W, H, x0, y0, side, size) {
		const k = colors.length;
		const votes = new Uint32Array(size * size * k), tot = new Uint32Array(size * size), cnt = new Uint32Array(size * size);
		for (let sy = 0; sy < side; sy++) {
			const y = y0 + sy, ty = Math.min(size - 1, (sy * size / side) | 0);
			for (let sx = 0; sx < side; sx++) {
				const x = x0 + sx, tx = Math.min(size - 1, (sx * size / side) | 0);
				const t = ty * size + tx; tot[t]++;
				if (x < 0 || y < 0 || x >= W || y >= H) continue;
				const l = labels[y * W + x];
				if (l < 0) continue;
				cnt[t]++; votes[t * k + l]++;
			}
		}
		const out = new Uint8ClampedArray(size * size * 4);
		for (let t = 0; t < size * size; t++) {
			if (!cnt[t] || cnt[t] / tot[t] < CONFIG.coverage) continue;
			let best = 0;
			for (let l = 1; l < k; l++) if (votes[t * k + l] > votes[t * k + best]) best = l;
			const rgb = colors[best];
			out[t * 4] = rgb[0]; out[t * 4 + 1] = rgb[1]; out[t * 4 + 2] = rgb[2]; out[t * 4 + 3] = 255;
		}
		return out;
	}

	// Centra el sprite en un lienzo 2 px mayor y pinta un contorno de 1 px alrededor de lo opaco.
	function addOutline(rgba, inner, size) {
		const out = new Uint8ClampedArray(size * size * 4);
		const off = (size - inner) >> 1;
		for (let y = 0; y < inner; y++) for (let x = 0; x < inner; x++) {
			const s = (y * inner + x) * 4, d = ((y + off) * size + x + off) * 4;
			for (let c = 0; c < 4; c++) out[d + c] = rgba[s + c];
		}
		const alpha = (x, y) => x >= 0 && y >= 0 && x < size && y < size && out[(y * size + x) * 4 + 3] === 255;
		const edge = [];
		for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
			if (alpha(x, y)) continue;
			if (alpha(x - 1, y) || alpha(x + 1, y) || alpha(x, y - 1) || alpha(x, y + 1)) edge.push((y * size + x) * 4);
		}
		for (const d of edge) { out[d] = OUTLINE[0]; out[d + 1] = OUTLINE[1]; out[d + 2] = OUTLINE[2]; out[d + 3] = 255; }
		return out;
	}

	function dist2(a, b) { const r = a[0] - b[0], g = a[1] - b[1], bl = a[2] - b[2]; return r * r + g * g + bl * bl; }
	function nearestIndex(p, centers) {
		let best = 0, bd = Infinity;
		for (let c = 0; c < centers.length; c++) { const d = dist2(p, centers[c]); if (d < bd) { bd = d; best = c; } }
		return best;
	}
	// Distancia "redmean": aproxima mejor la percepción humana que la euclídea simple.
	function redmean(a, p) {
		const rm = (a[0] + p[0]) / 2, dr = a[0] - p[0], dg = a[1] - p[1], db = a[2] - p[2];
		return (2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db;
	}

	async function encode(rgba, size) {
		const c = new OffscreenCanvas(size, size);
		c.getContext("2d").putImageData(new ImageData(rgba, size, size), 0, 0);
		const blob = await c.convertToBlob({ type: "image/png" });
		const buf = new Uint8Array(await blob.arrayBuffer());
		let s = ""; for (const b of buf) s += String.fromCharCode(b);
		return "data:image/png;base64," + btoa(s);
	}

	window.SpritePipeline = { CONFIG, queueAll, collect, reprocess, workflow, processImage, state };
})();
