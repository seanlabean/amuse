module import

contains

! This module is designed to work along the MUSE library.
! It takes an array with pressure, density, mass coordinate and
! composition for each mesh point (to be extended with angular momentum)
! and constructs a new stellar model, in the vein of mkmergermod.
! This facility is forked off to its own module because (for the moment)
! it makes use of numerical recipes code that shouldn't taint the main
! library file.
! Order of variables stored at each meshpoint:
!  Mass coordinate [Msun], Radius [Rsun], log density [cgs],
!  log pressure [cgs], XH, XHE, XC, XN, XO, XNE, XMG, XSI, XFE
! Mespoints should be passed in from *surface* to *centre*
function import_stellar_merger(nmesh, numvar, model, age_tag)
   use real_kind
   use twinlib
   use control
   use mesh_enc
   use constants
   use settings
   use init_dat
   use atomic_data
   use test_variables
   use interpolate
   use binary_history, only: hpr
   use indices
   
   implicit none
   integer :: import_stellar_merger
   integer, intent(in) :: nmesh, numvar
   real(double), intent(in) :: model(numvar, nmesh)
   real(double), intent(in) :: age_tag
   real(double) :: xa(9), na(9)

   type(init_dat_settings) :: initdat
   integer :: kh2, ksv, kt5, jch
   integer :: n, i, star_id, iter, status
   real(double) :: mass, entropy_max, target_diffsqr, vma, tkh, composition_msq
   character(len=500) :: outputfilename, basename

   basename = "star"

   call push_init_dat(initdat, kh2, ksv, kt5, jch)
!~   kr2 = get_number_of_iterations()
   kx = 0
   ky = 0
   kz = 0
   !> \todo FIXME: there are more mixing and mass loss options that can be
   !! set in the init.dat file, these need to be stored/restored as
   !! well!
   !<
   cth = 0.0
   crd = 0.0
   smart_mass_loss = 0.0  ! Elaborate mass loss routine on or off
   cmr   =  0.0           ! Reimers-like wind (RGB/AGB)
   cmrr  =  0.0           ! Real Reimers wind (RGB/AGB)
   cmsc  =  0.0           ! Schroeder & Cuntz wind (RGB/AGB)
   cmvw  =  0.0           ! Vasiliadis & Wood (AGB)
   cmw   =  0.0           ! Wachter & al. (AGB)
   cmal  =  0.0           ! Achmad & al. (yellow supergiant)
   cmj   =  0.0           ! de Jager & al. (luminous stars)
   cmv   =  0.0           ! Vink & al. (O/B stars)
   cmk   =  0.0           ! Kudritzki 2002 (very luminous O stars)
   cmnl  =  0.0           ! Nugis & Lamers (Wolf-Rayet)           
   mass = model(1, 1)

   ! Invert equation of state
   print *, 'inverting eos...'
   do n=1, nmesh
      ! Convert mass fractions back baryon number fractions
      na(1:9) = model(5:13, n)
      do i=1, 9
         xa(i) = na(i) * cbn(i)/can(i)
      end do
      vma = sum(xa(1:9))
      xa(1:9) = xa(1:9) / vma
      th(VAR_MASS, n) = model(1, n) * cmsn    ! Mass coordinate
      th(VAR_H1, n) = xa(1)                 ! Hydrogen abundance
      th(VAR_HE4, n) = xa(2)
      th(VAR_C12, n) = xa(3)
      th(VAR_N14, n) = xa(4)
      th(VAR_O16, n) = xa(5)
      th(VAR_NE20, n) = xa(6)
      th(VAR_MG24, n) = xa(7)
      th(VAR_SI28, n) = xa(8)
      th(VAR_FE56, n) = xa(9)
      call prtoft (model(4, n), model(3, n), th(VAR_LNF, n), th(VAR_LNT, n), xa)
   end do
   ip_mesh_size = nmesh

   ! Construct interpolation tables
   print *, 'constructing interpolation tables'
   do n = 1, 16
      call iptable_init (nmesh, th(VAR_MASS,:),th(n,:),thb(n,:),thc(n,:),thd(n,:))
   end do

   print *, 'loading zams star of mass', mass
   call flush_star
   status = new_zams_star(star_id, mass, 0.0d0)
   if (status /= 0) then
      print *, '*** failed to create new zamsn star. Returned with code:', status
      stop
   end if
   call select_star(star_id)

   ! Stage 1: match composition
   adj_comp = .true.
   impose_composition_factor = 0.0d0
   do iter=1, 100
      print *, 'composition adjustment factor =', impose_composition_factor

      ! Make sure the timestep is suitably long
      tkh = 1.0d22*cg*h(VAR_MASS, 1)*2/(exp(h(VAR_LNR, 1))*h(VAR_LUM, 1)*csy)
      do while (status == 0 .and. dt < tkh)
         !print *, 'Grow timestep'
         dt = 1.1*dt
         status = evolve_one_timestep(star_id)
      end do

      status = evolve_one_timestep(star_id)
      call flush_star()
      if (status /= 0) then
         print *, '*** failed to converge on timestep', iter, 'with code', status
         stop
      end if

      composition_msq = get_composition_mean_square();
      print *, 'Converged to MSQ error', composition_msq

      if (composition_msq < 1.0d-8) exit
      !if (impose_composition_factor>=1.0d0) exit
      impose_composition_factor = min(3.0d0*impose_composition_factor, 1.0d0);
      !if (impose_composition_factor<=1.0d-2) then
      !   impose_composition_factor = min(1.5d0*impose_composition_factor, 1.0d0);
      !else
      !   impose_composition_factor = min(1.2d0*impose_composition_factor, 1.0d0);
      !end if
      impose_composition_factor = max(impose_composition_factor, 1.0d-4);

      flush(6)
   end do

   ! Store output
   call flush_star()
   outputfilename = trim(basename)//'.comp_mod'
   print *, 'writing output to ', trim(outputfilename)
   call dump_twin_model(star_id, outputfilename);

   ! Bring the star in thermal equilibrium
   print *, "Thermalising..."
   status = evolve_one_timestep(star_id)
   tkh = 1.0d22*cg*h(VAR_MASS, 1)*2/(exp(h(VAR_LNR, 1))*h(VAR_LUM, 1)*csy)
   do while (status == 0 .and. dt < 10.0*tkh)
      !print *, 'Grow timestep'
      dt = 1.01*dt
      status = evolve_one_timestep(star_id)
   end do
 
   call flush_star()
   outputfilename = trim(basename)//'.comp_mod_therm'
   print *, 'writing output to ', trim(outputfilename)
   call dump_twin_model(star_id, outputfilename)

   ! Stage 2: adjust entropy profile, keep composition fixed
   usemenc = .true.
   mutation_mode = MMODE_EV
   impose_entropy_factor = 0.0d0
   entropy_max = 1.0d2
   curr_diffsqr = 1.0d3
   best_diffsqr = 1.0d3
   target_diffsqr = eps
   target_diffsqr = 1.0e-4
   call set_number_of_iterations(20)
   do iter=1, 100
      age = 0.0
      print *, 'entropy adjustment factor =', impose_entropy_factor
      ! Construct the next stellar model in the pseudo-evolution
      ! sequence. Make sure the timestep is always close to the
      ! thermal time scale for the best accuracy. Make sure the
      ! solution is stable at this timestep by iterating on it while
      ! only changing the timestep.
      status = evolve_one_timestep(star_id)
      tkh = 1.0d22*cg*h(VAR_MASS, 1)*2/(exp(h(VAR_LNR, 1))*h(VAR_LUM, 1)*csy)
      do while (status == 0 .and. dt < 10.0*csy)
         !print *, 'Grow timestep'
         dt = 1.01*dt
         status = evolve_one_timestep(star_id)
      end do
      do while (status == 0 .and. dt > tkh * csy)
         !print *, 'Shrink timestep'
         dt = dt*0.8
         status = evolve_one_timestep(star_id)
      end do
      !print *, DT/CSY, TKH
      dt = tkh * csy
      call flush_star()
      if (status /= 0) then
         print *, '*** failed to converge on timestep', iter, 'with code', status
         if (impose_entropy_factor >= 1.0d0) exit;
         stop
      end if

      ! Check convergence, adjust entropy matching factor
      call check_conv_to_target_structure()
      if ( curr_diffsqr < best_diffsqr ) then
         best_diffsqr = curr_diffsqr
         best_mod = iter
         mutant_h(:, 1:kh) = h(:, 1:kh)
      end if
      !WRITE (6, '(1P, 3D16.9, I6)'), CURR_MAXDIFFSQR, CURR_DIFFSQR, BEST_DIFFSQR, BEST_MOD
      print *, 'converged to',best_diffsqr,'at',best_mod,'now', curr_diffsqr, 'at',iter


      if ( ( impose_entropy_factor>=entropy_max .and. best_diffsqr>curr_diffsqr ) .or. best_diffsqr<target_diffsqr ) exit
      if (impose_entropy_factor < 0.7) then
         impose_entropy_factor = min(1.5d0*impose_entropy_factor, entropy_max);
      else if (impose_entropy_factor < 1.0) then
         impose_entropy_factor = min(1.1d0*impose_entropy_factor, entropy_max);
      else if (impose_entropy_factor < 1.0d2) then
         impose_entropy_factor = min(1.05d0*impose_entropy_factor, entropy_max);
      else if (impose_entropy_factor < 1.0d3) then
         impose_entropy_factor = min(1.05d0*impose_entropy_factor, entropy_max);
      else
         impose_entropy_factor = min(1.01d0*impose_entropy_factor, entropy_max);
      end if
      impose_entropy_factor = max(impose_entropy_factor, 1.0d-8);

      flush(6)
   end do

   call pop_init_dat(initdat, kh2, ksv, kt5, jch)
   h(:, 1:kh) = mutant_h(:, 1:kh)
   hpr(:, 1:kh) = mutant_h(:, 1:kh)
   adj_comp = .false.
   usemenc = .false.
   impose_entropy_factor = 0.0d0
   impose_composition_factor = 0.0d0
   ! Set timestep
   !DT = 1.0D3 * CSY
   dt = tkh * csy
   ! Set age: make sure this is not reset when we go back one model
   age = age_tag
   prev(10) = age
   pprev(10) = age
   call flush_star()
   call set_star_iter_parameters( star_id, 10, 20, 0 )

   ! Store output
   outputfilename = trim(basename)//'.pmutate'
   print *, 'writing output to ', trim(outputfilename)
   call dump_twin_model(star_id, outputfilename);

   import_stellar_merger = star_id
end function import_stellar_merger


   ! Each shell has: Mass coordinate [Msun], Radius [Rsun], density [cgs],
   !  pressure [cgs], XH, XHE, XC, XN, XO, XNE, XMG, XSI, XFE
   ! Meshpoints should be passed in from *surface* to *centre*
   integer function new_stellar_model(star_id, mass, radius, rho, pressure, &
         XH, XHE, XC, XN, XO, XNE, XMG, XSI, XFE, n)
      use real_kind
      use twinlib
      use mesh, only: max_nm
      implicit none
      integer, intent(out) :: star_id
      integer, intent(in) :: n
      double precision, intent(in) :: mass(n), radius(n), rho(n), pressure(n), &
         XH(n), XHE(n), XC(n), XN(n), XO(n), XNE(n), XMG(n), XSI(n), XFE(n)
      double precision :: logrho(n), logpressure(n)
      real(double), pointer :: new_model(:,:)
      
      if (n < 3) then
         new_stellar_model = -31   ! Too few shells in new empty model
         return
      else if (n > max_nm) then
         new_stellar_model = -32   ! Too many shells in new empty model
         return
      else
         allocate(new_model(13, n))
         new_stellar_model = 0    ! A new empty model was defined
      endif
      
      new_model(1, 1:n) = mass(1:n)
      new_model(2, 1:n) = radius(1:n)
      logrho(1:n) = log(rho(1:n))
      logpressure(1:n) = log(pressure(1:n))
      new_model(3, 1:n) = logrho(1:n)
      new_model(4, 1:n) = logpressure(1:n)
      new_model(5, 1:n) = XH
      new_model(6, 1:n) = XHE
      new_model(7, 1:n) = XC
      new_model(8, 1:n) = XN
      new_model(9, 1:n) = XO
      new_model(10, 1:n) = XNE
      new_model(11, 1:n) = XMG
      new_model(12, 1:n) = XSI
      new_model(13, 1:n) = XFE
      star_id = import_stellar_merger(n, 13, new_model, 0.0d0)
      deallocate(new_model)
   end function
   

end module
