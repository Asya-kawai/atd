// Automatically generated; do not edit
package com.mylife.test;
import argonaut._, Argonaut._
/**
 * wibble
 */
case class ComplexRecord(
  b : Boolean,
  i : Int,
  s : String,
  l : List[Boolean],
  m : List[List[Int]],
  sample_sum : SampleSum,
  class_ : Option[Int],
  final_ : Option[Int],
  kase : String,
  l2 : List[RecordWithDefaults],
) extends Atds {

  override def toJson: Json = Json(
    "b" := b,
    "i" := i,
    "s" := s,
    "l" := l,
    "m" := m,
    "sample_sum" := sample_sum,
    "class" := class_,
    "final" := final_,
    "case" := kase,
    "l2" := l2,
  )
}
