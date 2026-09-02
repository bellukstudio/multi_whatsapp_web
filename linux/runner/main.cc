#include <malloc.h>
#include "my_application.h"

int main(int argc, char** argv) {
  // OPTIMASI LEVEL SISTEM (Advanced glibc Tuning)
  // Membatasi "Arena" memori per CPU. Sangat penting untuk WebKit yang Multi-Process.
  mallopt(M_ARENA_MAX, 1);
  
  /**
   * PENTING: M_MMAP_THRESHOLD
   * WhatsApp sering mengolah gambar/media besar (>128KB). glibc biasanya meng-alokasi ini di MMAP area 
   * yang sulit dibersihkan. Menaikkan threshold ini memaksa sistem mengelola data di heap yang 
   * lebih mudah dirilis ke sistem oleh malloc_trim().
   */
  mallopt(M_MMAP_THRESHOLD, 1024 * 1024); // 1MB

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}