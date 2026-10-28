variable "phase" {
  type    = string
  default = "baseline"
  validation {
    condition     = contains(["baseline", "upgrade", "rollback", "repair"], var.phase)
    error_message = "Use baseline, upgrade, rollback, or repair. Run the documented sequence."
  }
}
locals {
  chart_path = "./fixtures/charts/${lookup({ baseline = "schema-v1", upgrade = "schema-v2", rollback = "schema-v1", repair = "schema-compatible" }, var.phase, "schema-v1")}"
  crd_policy = var.phase == "rollback" ? "Skip" : "CreateReplace"
}
