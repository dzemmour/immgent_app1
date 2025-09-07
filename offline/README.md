---
output:
  pdf_document: default
  html_document: default
---
# immgenT Explorer (Seurat Shiny App)

An interactive Shiny app for exploring immgenT Seurat objects with hierarchical filters (choose your experiment > batch (IGT) > sample exp/IGT/sample), FeaturePlot & DimPlot (with adjustable dot size), and a metadata summary table for the loaded samples. You can upload your own `.rds` / `.RData` Seurat object or point the app at a local folder of demo objects.

**Image:** `immgent_app1:0.1`
**Port:** `3838` (HTTP)
**CPU/GPU:** CPU only
**Architecture:** built for **linux/amd64/**

---

## 1) What’s inside

In the UI you can choose:

* **Upload a file** — upload a Seurat `.rds` / `.RData`.
* **Use bundled immgenT demo dataset** 

The seurat object requires:

* **RNA counts**
* a reduction named as: **mde_incremental**
* sample name in the column **sample_code**

immgenT datasets can be download from: 

---

## 2) Easiest way (no terminal): Docker Desktop

1. **Install Docker Desktop**

   * Download Docker Desktop **[https://www.docker.com/products/docker-desktop/]** 
   * Install it
   * Open it (!) and go through the default setup (login can be skipped) once until it says “Docker engine running”.

2. **Recommended: Increase memory/CPU for bigger objects**

   * Docker Desktop → **Settings** → **Resources**:

     * **Memory:** 8–16 GB (more for very large datasets)
     * **CPUs:** 4+ cores
     * Click **Apply & Restart**

3. **Run the app**

   * Open the folder immgenT_App1
   * Windows: Click **open_windows.bat**
   * Mac: 
       * Click **open_mac.command** 
       * The app won't open until you authorize it: Go to your computer's **Settings → Security settings**
   * The Terminal will open, the code will run. It takes a minute so be patient.
   * Your browser should open to **[http://localhost:3838](http://localhost:3838)**

4. **In the app**

   * Choose **Upload a file** (if you’ll upload), or
   * Choose **Use bundled demo**

5. **Start/Stop later**

   * Close the terminal


## 3) Performance & memory tips

* In Docker Desktop → **Settings → Resources**, increase **Memory** (8–16 GB+) and **CPUs** (4+) if you work with large Seurat objects.
* Close other containers/apps to free RAM.
* If a dataset is huge, try subsetting/downsampling before loading.


## 4) About

* **App:** immgenT Explorer (Seurat Shiny)
* **Maintainer:** David Zemmour (dzemmour)
* **Tag:** `0.1`
* **License:** MIT license

