# immgenT_App1/Dockerfile
FROM rocker/shiny:4.4.2

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev libssl-dev libxml2-dev libgit2-dev \
    libharfbuzz-dev libfribidi-dev libfreetype6-dev libpng-dev \
    libtiff5-dev libjpeg-dev libfontconfig1-dev libglpk-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/shiny-server
COPY . /srv/shiny-server/

# Install runtime R deps (no renv, no BPCells)
#RUN R -e 'install.packages(c("shiny","Seurat","dplyr","ggplot2","DT", "ZemmourLib"))'
RUN R -q -e 'options(Ncpus=parallel::detectCores()); \
             install.packages(c("shiny","Seurat","dplyr","ggplot2","DT","remotes"), repos="https://cran.r-project.org"); \
             remotes::install_github("dzemmour/ZemmourLib", dependencies = FALSE, upgrade="never")'

RUN chown -R shiny:shiny /srv/shiny-server
EXPOSE 3838
USER shiny
CMD ["/usr/bin/shiny-server"]
