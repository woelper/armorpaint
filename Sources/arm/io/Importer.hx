package arm.io;

import kha.Font;
import kha.arrays.Int16Array;
import iron.data.SceneFormat;
import iron.data.MeshData;
import iron.data.Data;
import iron.math.Vec4;
import iron.Scene;
import arm.util.MeshUtil;
import arm.util.UVUtil;
import arm.util.ViewportUtil;
import arm.util.Path;
import arm.ui.UITrait;
import arm.ui.UIView2D;
import arm.ui.UINodes;
import arm.Project;
import arm.Tool;
using StringTools;

class Importer {

	public static var fontList = ["default.ttf"];
	public static var fontMap = new Map<String, Font>();
	public static var clearLayers = true;

	public static function importFile(path:String, dropX = -1.0, dropY = -1.0) {
		// Mesh
		if (Path.checkMeshFormat(path)) {
			importMesh(path);
		}
		// Image
		else if (Path.checkTextureFormat(path)) {
			ImportTexture.run(path);
			// Place image node
			var x0 = UINodes.inst.wx;
			var x1 = UINodes.inst.wx + UINodes.inst.ww;
			if (UINodes.inst.show && dropX > x0 && dropX < x1) {
				UINodes.inst.acceptDrag(Project.assets.length - 1);
				UINodes.inst.nodes.nodesDrag = false;
				UINodes.inst.hwnd.redraws = 2;
			}
		}
		// Font
		else if (Path.checkFontFormat(path)) {
			ImportFont.run(path);
		}
		// Project
		else if (Path.checkProjectFormat(path)) {
			ImportArm.runProject(path);
		}
		// Plugin
		else if (Path.checkPluginFormat(path)) {
			ImportPlugin.run(path);
		}
		// Folder
		else if (path.indexOf(".") == -1) {
			ImportFolder.run(path);
		}
		else {
			Log.showError(Strings.error1);
		}
	}

	public static function importMesh(path:String, _clearLayers = true) {
		if (!Path.checkMeshFormat(path)) {
			Log.showError(Strings.error1);
			return;
		}

		clearLayers = _clearLayers;

		#if arm_debug
		var timer = iron.system.Time.realTime();
		#end

		var p = path.toLowerCase();
		if (p.endsWith(".obj")) ImportObj.run(path);
		else if (p.endsWith(".fbx")) ImportFbx.run(path);
		else if (p.endsWith(".stl")) ImportStl.run(path);
		else if (p.endsWith(".blend")) ImportBlend.run(path);

		if (Context.mergedObject != null) {
			Context.mergedObject.remove();
			Data.deleteMesh(Context.mergedObject.data.handle);
			Context.mergedObject = null;
		}

		Context.selectPaintObject(Context.mainObject());

		if (Project.paintObjects.length > 1) {
			// Sort by name
			Project.paintObjects.sort(function(a, b):Int {
				if (a.name < b.name) return -1;
				else if (a.name > b.name) return 1;
				return 0;
			});

			// No mask by default
			if (Context.mergedObject == null) MeshUtil.mergeMesh();
			Context.paintObject.skip_context = "paint";
			Context.mergedObject.visible = true;
		}
		Project.meshAssets = [path];

		if (UITrait.inst.worktab.position == SpacePaint) {
			ViewportUtil.scaleToBounds();
		}

		if (Context.paintObject.name == "") Context.paintObject.name = "Object";
		arm.nodes.MaterialParser.parseMeshMaterial();

		UIView2D.inst.hwnd.redraws = 2;

		#if arm_debug
		trace("Mesh imported in " + (iron.system.Time.realTime() - timer));
		#end

		#if kha_direct3d12
		arm.render.RenderPathRaytrace.ready = false;
		#end
	}

	public static function makeMesh(mesh:Dynamic, path:String) {
		if (mesh == null || mesh.posa == null || mesh.nora == null || mesh.inda == null) {
			Log.showError(Strings.error3);
			return;
		}

		var raw:TMeshData = null;
		if (UITrait.inst.worktab.position == SpaceScene) {
			raw = {
				name: mesh.name,
				vertex_arrays: [
					{ values: mesh.posa, attrib: "pos" },
					{ values: mesh.nora, attrib: "nor" }
				],
				index_arrays: [
					{ values: mesh.inda, material: 0 }
				],
				scale_pos: mesh.scalePos,
				scale_tex: mesh.scaleTex
			};
			if (mesh.texa != null) raw.vertex_arrays.push({ values: mesh.texa, attrib: "tex" });
		}
		else {

			if (mesh.texa == null) {
				Log.showError(Strings.error4);
				var verts = Std.int(mesh.posa.length / 4);
				mesh.texa = new Int16Array(verts * 2);
				var n = new Vec4();
				for (i in 0...verts) {
					n.set(mesh.posa[i * 4] / 32767, mesh.posa[i * 4 + 1] / 32767, mesh.posa[i * 4 + 2] / 32767).normalize();
					// Sphere projection
					// mesh.texa[i * 2    ] = Math.atan2(n.x, n.y) / (Math.PI * 2) + 0.5;
					// mesh.texa[i * 2 + 1] = n.z * 0.5 + 0.5;
					// Equirect
					mesh.texa[i * 2    ] = Std.int(((Math.atan2(-n.z, n.x) + Math.PI) / (Math.PI * 2)) * 32767);
					mesh.texa[i * 2 + 1] = Std.int((Math.acos(n.y) / Math.PI) * 32767);
				}
			}
			raw = {
				name: mesh.name,
				vertex_arrays: [
					{ values: mesh.posa, attrib: "pos" },
					{ values: mesh.nora, attrib: "nor" },
					{ values: mesh.texa, attrib: "tex" }
				],
				index_arrays: [
					{ values: mesh.inda, material: 0 }
				],
				scale_pos: mesh.scalePos,
				scale_tex: mesh.scaleTex
			};
		}

		new MeshData(raw, function(md:MeshData) {

			// Append
			if (UITrait.inst.worktab.position == SpaceScene) {
				var mats = new haxe.ds.Vector(1);
				mats[0] = Context.materialScene.data;
				var object = Scene.active.addMeshObject(md, mats, Scene.active.getChild("Scene"));
				path = path.replace("\\", "/");
				var ar = path.split("/");
				var s = ar[ar.length - 1];
				object.name = s.substring(0, s.length - 4);

				// md.geom.calculateAABB();
				// var aabb = md.geom.aabb;
				// var dim = new TFloat32Array(3);
				// dim[0] = aabb.x;
				// dim[1] = aabb.y;
				// dim[2] = aabb.z;
				// object.raw.dimensions = dim;
				#if arm_physics
				object.addTrait(new armory.trait.physics.RigidBody(0.0));
				#end

				Context.selectObject(object);
			}
			// Replace
			else {
				Context.paintObject = Context.mainObject();

				Context.selectPaintObject(Context.mainObject());
				for (i in 0...Project.paintObjects.length) {
					var p = Project.paintObjects[i];
					if (p == Context.paintObject) continue;
					Data.deleteMesh(p.data.handle);
					p.remove();
				}
				var handle = Context.paintObject.data.handle;
				if (handle != "SceneSphere" && handle != "ScenePlane") {
					Data.deleteMesh(handle);
				}

				if (clearLayers) {
					while (Project.layers.length > 1) { var l = Project.layers.pop(); l.unload(); }
					Context.setLayer(Project.layers[0]);
					iron.App.notifyOnRender(Layers.initLayers);
					History.reset();
				}

				Context.paintObject.setData(md);
				Context.paintObject.name = mesh.name;

				var g = Context.paintObject.data.geom;
				var posbuf = g.vertexBufferMap.get("pos");
				if (posbuf != null) { // Remove cache
					posbuf.delete();
					g.vertexBufferMap.remove("pos");
				}

				Project.paintObjects = [Context.paintObject];
			}

			md.handle = raw.name;
			Data.cachedMeshes.set(md.handle, md);

			Context.ddirty = 4;
			UITrait.inst.hwnd.redraws = 2;
			UITrait.inst.hwnd1.redraws = 2;
			UITrait.inst.hwnd2.redraws = 2;
			UVUtil.uvmapCached = false;
			UVUtil.trianglemapCached = false;
		});
	}

	public static function addMesh(mesh:Dynamic) {

		if (mesh.texa == null) {
			Log.showError(Strings.error4);
			var verts = Std.int(mesh.posa.length / 4);
			mesh.texa = new Int16Array(verts * 2);
			var n = new Vec4();
			for (i in 0...verts) {
				n.set(mesh.posa[i * 4] / 32767, mesh.posa[i * 4 + 1] / 32767, mesh.posa[i * 4 + 2] / 32767).normalize();
				// Sphere projection
				// mesh.texa[i * 2    ] = Math.atan2(n.x, n.y) / (Math.PI * 2) + 0.5;
				// mesh.texa[i * 2 + 1] = n.z * 0.5 + 0.5;
				// Equirect
				mesh.texa[i * 2    ] = Std.int(((Math.atan2(-n.z, n.x) + Math.PI) / (Math.PI * 2)) * 32767);
				mesh.texa[i * 2 + 1] = Std.int((Math.acos(n.y) / Math.PI) * 32767);
			}
		}
		var raw:TMeshData = {
			name: mesh.name,
			vertex_arrays: [
				{ values: mesh.posa, attrib: "pos" },
				{ values: mesh.nora, attrib: "nor" },
				{ values: mesh.texa, attrib: "tex" }
			],
			index_arrays: [
				{ values: mesh.inda, material: 0 }
			],
			scale_pos: mesh.scalePos,
			scale_tex: mesh.scaleTex
		};

		new MeshData(raw, function(md:MeshData) {

			var object = Scene.active.addMeshObject(md, Context.paintObject.materials, Context.paintObject);
			object.name = mesh.name;
			object.skip_context = "paint";

			Project.paintObjects.push(object);

			md.handle = raw.name;
			Data.cachedMeshes.set(md.handle, md);

			Context.ddirty = 4;
			UITrait.inst.hwnd.redraws = 2;
			UVUtil.uvmapCached = false;
			UVUtil.trianglemapCached = false;
		});
	}
}
