# Alpine Swift Migration Dashboard

An interactive R Shiny dashboard that visualises the trans-Saharan migration of the Alpine Swift (Tachymarptis melba, formerly Apus melba).

## Access to a hosted Dashboard

The Dashboard is hosted on https://rolfruettli-dashboard-alpine-swift.hf.space/ on `Huggingface`. Please note that starting up the Dashboard can take a few minutes upon visiting the link. Also the Dashboard might not display the best performance, as the Huggingface free tier only features limited computing capabilities.

## Set-up for yourself

To run the dashboard locally, follow these steps in order:

### 1) Installing Packages

First, install the required dependencies. A first try might be to run the `_setup.R` script in an R session to install the required packages. This might or might not work perfectly depending on your operating system type (Windows, Mac, Linux).

```r
source("_setup.R")
```

Another possibility is to install a conda environment using the `environment.yml`. This will most likely only work on Linux systems and the `environment.yml` file was built on a `Linux Ubuntu` machine. A convenient way for `Windows` users to get quick access to a Linux distribution is to activate the `Windows Subsystem for Linux` and then installing a `Linux Distro` like `Ubuntu` or `Fedora`.

### 2) Run the application

After the environment is ready, start the Shiny app by running `app.R`.
