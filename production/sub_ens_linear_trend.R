unlink(".RData")
args_in <- readLines("input_text_linear_trend")

netCDF.files <- args_in[1:3]
variable <- args_in[4]
region <- args_in[5]
landcover <- args_in[6]
language <- args_in[7]
stat_var <- args_in[8]
run_id <- args_in[9]
output_path <- args_in[10]
output_csv <- args_in[11]


library(KlimaKonformC3)


plot_name <- paste0(
  output_path,
  variable, "_",
  "ensemble_",
  run_id, "_lauf_",
  "3XRCPs_LT_.png"
)

# if(!file.exists(plot_name) ){#| file.size(plot_name)==0){
ens_linear_trend(
  netCDF.files,
  variable,
  region,
  landcover,
  stat_var,
  language,
  run_id,
  output_path,
  output_csv
)
# }
