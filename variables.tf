variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  type = list(string)
}

variable "address_prefixes" {
  type = map(list(string))
}

variable "user" {
  type = string
}

variable "password" {
  type = string
}